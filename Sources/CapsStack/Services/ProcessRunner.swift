import Darwin
import Foundation

/// The complete, non-interactive invocation passed to a CLI process.
struct ProcessSpecification: Sendable {
    let executableURL: URL
    let arguments: [String]
    let standardInput: Data?
    let currentDirectoryURL: URL?
    let environment: [String: String]?

    init(
        executableURL: URL,
        arguments: [String] = [],
        standardInput: Data? = nil,
        currentDirectoryURL: URL? = nil,
        environment: [String: String]? = nil
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.standardInput = standardInput
        self.currentDirectoryURL = currentDirectoryURL
        self.environment = environment
    }
}

struct ProcessResult: Sendable {
    let terminationStatus: Int32
    let standardOutput: Data
    let standardError: Data
    let didTruncateOutput: Bool

    var succeeded: Bool { terminationStatus == 0 }
}

enum ProcessRunnerError: LocalizedError, Equatable {
    case invalidExecutable(URL)
    case failedToLaunch(String)
    case timedOut
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidExecutable(let url):
            return "実行ファイルが見つかりません: \(url.path)"
        case .failedToLaunch(let message):
            return "プロセスを起動できませんでした: \(message)"
        case .timedOut:
            return "プロセスがタイムアウトしました。"
        case .cancelled:
            return "プロセスがキャンセルされました。"
        }
    }
}

protocol ProcessRunning: AnyObject, Sendable {
    func run(_ specification: ProcessSpecification, timeout: TimeInterval) async throws -> ProcessResult
}

/// A small Process wrapper with deterministic stdin/stdout handling and a hard timeout.
///
/// The process is never started through a shell. This is important for both security and
/// reproducibility: the selected CLI path and arguments are passed directly to Foundation's
/// Process API.
final class ProcessRunner: ProcessRunning, @unchecked Sendable {
    private let outputLimit: Int

    init(outputLimit: Int = 8 * 1024 * 1024) {
        self.outputLimit = max(1, outputLimit)
    }

    func run(_ specification: ProcessSpecification, timeout: TimeInterval) async throws -> ProcessResult {
        guard FileManager.default.isExecutableFile(atPath: specification.executableURL.path) else {
            throw ProcessRunnerError.invalidExecutable(specification.executableURL)
        }

        let process = Process()
        process.executableURL = specification.executableURL
        process.arguments = specification.arguments
        process.currentDirectoryURL = specification.currentDirectoryURL

        var environment = ProcessInfo.processInfo.environment
        if let overrides = specification.environment {
            environment.merge(overrides) { _, new in new }
        }
        process.environment = environment

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let inputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        if specification.standardInput != nil {
            process.standardInput = inputPipe
        }

        let state = ProcessRunState()
        return try await withTaskCancellationHandler(operation: {
            if Task.isCancelled { throw ProcessRunnerError.cancelled }
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ProcessResult, Error>) in
                let stdoutCollector = BoundedDataCollector(limit: self.outputLimit)
                let stderrCollector = BoundedDataCollector(limit: self.outputLimit)
                let outputGroup = DispatchGroup()
                let timeoutInterval = max(0.1, timeout)

                // Register and start both bounded readers before launch. This avoids losing output
                // when a short-lived child exits before the parent has installed its readers.
                Self.startReader(
                    outputPipe.fileHandleForReading,
                    collector: stdoutCollector,
                    group: outputGroup
                )
                Self.startReader(
                    errorPipe.fileHandleForReading,
                    collector: stderrCollector,
                    group: outputGroup
                )

                process.terminationHandler = { terminatedProcess in
                    // Descendants can inherit stdout/stderr and keep a pipe open after the direct
                    // child exits. Give normal readers a short drain window, then close our read
                    // handles so completion can never wait forever on an unrelated descendant.
                    if outputGroup.wait(timeout: .now() + 1) == .timedOut {
                        try? outputPipe.fileHandleForReading.close()
                        try? errorPipe.fileHandleForReading.close()
                        _ = outputGroup.wait(timeout: .now() + 0.25)
                    }
                    let stdoutResult = stdoutCollector.snapshot()
                    let stderrResult = stderrCollector.snapshot()

                    guard let completion = state.complete() else { return }
                    switch completion {
                    case .timedOut:
                        continuation.resume(throwing: ProcessRunnerError.timedOut)
                    case .cancelled:
                        continuation.resume(throwing: ProcessRunnerError.cancelled)
                    case .normal:
                        continuation.resume(returning: ProcessResult(
                            terminationStatus: terminatedProcess.terminationStatus,
                            standardOutput: stdoutResult.data,
                            standardError: stderrResult.data,
                            didTruncateOutput: stdoutResult.truncated || stderrResult.truncated
                        ))
                    }
                }

                do {
                    try process.run()
                    let pid = process.processIdentifier
                    if setpgid(pid, pid) == 0 {
                        state.setProcessGroupID(pid)
                    }
                } catch {
                    try? outputPipe.fileHandleForWriting.close()
                    try? errorPipe.fileHandleForWriting.close()
                    try? outputPipe.fileHandleForReading.close()
                    try? errorPipe.fileHandleForReading.close()
                    guard state.failLaunch() else { return }
                    continuation.resume(throwing: ProcessRunnerError.failedToLaunch(error.localizedDescription))
                    return
                }

                if let input = specification.standardInput {
                    // Writing on a utility queue prevents a large prompt from blocking the
                    // caller. Closing stdin is essential for CLIs that wait for EOF.
                    DispatchQueue.global(qos: .utility).async {
                        defer { try? inputPipe.fileHandleForWriting.close() }
                        try? inputPipe.fileHandleForWriting.write(contentsOf: input)
                    }
                }

                let workItem = DispatchWorkItem {
                    state.requestTermination(
                        reason: .timedOut,
                        process: process,
                        inputHandle: specification.standardInput == nil
                            ? nil
                            : inputPipe.fileHandleForWriting
                    )
                }
                state.setTimeoutWorkItem(workItem)
                DispatchQueue.global(qos: .utility).asyncAfter(
                    deadline: .now() + timeoutInterval,
                    execute: workItem
                )

                if Task.isCancelled {
                    state.requestTermination(
                        reason: .cancelled,
                        process: process,
                        inputHandle: specification.standardInput == nil
                            ? nil
                            : inputPipe.fileHandleForWriting
                    )
                }
            }
        }, onCancel: {
            state.requestTermination(
                reason: .cancelled,
                process: process,
                inputHandle: specification.standardInput == nil
                    ? nil
                    : inputPipe.fileHandleForWriting
            )
        })
    }

    private static func startReader(
        _ handle: FileHandle,
        collector: BoundedDataCollector,
        group: DispatchGroup
    ) {
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            defer { group.leave() }
            do {
                while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
                    collector.store(chunk)
                }
            } catch {
                // Closing the handle is the bounded escape hatch when a descendant keeps a pipe
                // alive. Output already collected remains valid and the process result records any
                // size truncation separately.
            }
        }
    }
}

private final class ProcessRunState: @unchecked Sendable {
    enum TerminationReason {
        case timedOut
        case cancelled
    }

    enum Completion {
        case normal
        case timedOut
        case cancelled
    }

    let lock = NSLock()
    var finished = false
    var terminationReason: TerminationReason?
    var processGroupID: pid_t?
    var timeoutWorkItem: DispatchWorkItem?

    func setProcessGroupID(_ id: pid_t) {
        lock.lock()
        processGroupID = id
        lock.unlock()
    }

    func setTimeoutWorkItem(_ item: DispatchWorkItem) {
        lock.lock()
        timeoutWorkItem = item
        let shouldCancel = finished
        lock.unlock()
        if shouldCancel { item.cancel() }
    }

    func requestTermination(
        reason: TerminationReason,
        process: Process,
        inputHandle: FileHandle?
    ) {
        lock.lock()
        if terminationReason == nil { terminationReason = reason }
        let shouldStop = !finished
        let groupID = processGroupID
        lock.unlock()
        guard shouldStop else { return }

        try? inputHandle?.close()
        if process.isRunning { process.terminate() }

        let pid = process.processIdentifier
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
            guard process.isRunning else { return }
            if groupID == pid {
                _ = Darwin.kill(-pid, SIGKILL)
            } else {
                _ = Darwin.kill(pid, SIGKILL)
            }
        }
    }

    /// Returns nil only when another callback already resumed the task.
    func complete() -> Completion? {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return nil }
        finished = true
        timeoutWorkItem?.cancel()
        switch terminationReason {
        case .timedOut: return .timedOut
        case .cancelled: return .cancelled
        case nil: return .normal
        }
    }

    func failLaunch() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return false }
        finished = true
        timeoutWorkItem?.cancel()
        return true
    }
}

private final class BoundedDataCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var data = Data()
    private var truncated = false

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    func store(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        let remaining = limit - data.count
        if remaining > 0 {
            data.append(chunk.prefix(remaining))
        }
        if chunk.count > max(0, remaining) {
            truncated = true
        }
    }

    func snapshot() -> (data: Data, truncated: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (data, truncated)
    }
}
