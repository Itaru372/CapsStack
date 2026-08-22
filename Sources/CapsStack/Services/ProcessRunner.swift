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

        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ProcessResult, Error>) in
                let state = ProcessRunState()
                let stdoutCollector = BoundedDataCollector(limit: self.outputLimit)
                let stderrCollector = BoundedDataCollector(limit: self.outputLimit)
                let outputGroup = DispatchGroup()
                let timeoutInterval = max(0.1, timeout)

                process.terminationHandler = { terminatedProcess in
                    // The readers below drain both pipes while the child is running. Waiting for
                    // them here is safe because process termination closes the pipe writers.
                    outputGroup.wait()
                    let stdoutResult = stdoutCollector.snapshot()
                    let stderrResult = stderrCollector.snapshot()

                    state.lock.lock()
                    guard !state.finished else {
                        state.lock.unlock()
                        return
                    }
                    state.finished = true
                    let timedOut = state.timedOut
                    state.timeoutWorkItem?.cancel()
                    state.lock.unlock()

                    if timedOut {
                        continuation.resume(throwing: ProcessRunnerError.timedOut)
                    } else {
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
                } catch {
                    state.lock.lock()
                    state.finished = true
                    state.lock.unlock()
                    continuation.resume(throwing: ProcessRunnerError.failedToLaunch(error.localizedDescription))
                    return
                }

                outputGroup.enter()
                DispatchQueue.global(qos: .utility).async {
                    stdoutCollector.store(outputPipe.fileHandleForReading.readDataToEndOfFile())
                    outputGroup.leave()
                }
                outputGroup.enter()
                DispatchQueue.global(qos: .utility).async {
                    stderrCollector.store(errorPipe.fileHandleForReading.readDataToEndOfFile())
                    outputGroup.leave()
                }

                if let input = specification.standardInput {
                    // Writing on a utility queue prevents a large prompt from blocking the
                    // caller. Closing stdin is essential for CLIs that wait for EOF.
                    DispatchQueue.global(qos: .utility).async {
                        inputPipe.fileHandleForWriting.write(input)
                        inputPipe.fileHandleForWriting.closeFile()
                    }
                }

                let workItem = DispatchWorkItem {
                    state.lock.lock()
                    guard !state.finished else {
                        state.lock.unlock()
                        return
                    }
                    state.timedOut = true
                    state.lock.unlock()
                    if process.isRunning {
                        process.terminate()
                    }
                }
                state.lock.lock()
                state.timeoutWorkItem = workItem
                state.lock.unlock()
                DispatchQueue.global(qos: .utility).asyncAfter(
                    deadline: .now() + timeoutInterval,
                    execute: workItem
                )
            }
        }, onCancel: {
            if process.isRunning {
                process.terminate()
            }
        })
    }
}

private final class ProcessRunState: @unchecked Sendable {
    let lock = NSLock()
    var finished = false
    var timedOut = false
    var timeoutWorkItem: DispatchWorkItem?
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
