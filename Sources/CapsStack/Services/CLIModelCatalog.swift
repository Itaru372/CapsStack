import Foundation

/// Reads a model catalog from a CLI without starting an agent session.
protocol CLIModelListing: AnyObject, Sendable {
    func models(for kind: CLIKind, executableOverride: String?) async throws -> [CLIModel]
}

enum CLIModelListingError: LocalizedError, Equatable {
    case unsupported(CLIKind)
    case executableNotFound(CLIKind)
    case timedOut(CLIKind)
    case processFailed(CLIKind)
    case invalidOutput(CLIKind)

    var errorDescription: String? {
        switch self {
        case .unsupported(let kind):
            return "\(kind.displayName) does not support model listing."
        case .executableNotFound(let kind):
            return "\(kind.displayName) executable was not found."
        case .timedOut(let kind):
            return "Timed out while fetching the \(kind.displayName) model list."
        case .processFailed(let kind):
            return "Could not fetch the model list from \(kind.displayName)."
        case .invalidOutput(let kind):
            return "Could not parse the \(kind.displayName) model list."
        }
    }
}

/// The model commands deliberately stay at the CLI boundary. We do not inspect provider config
/// files or call provider APIs ourselves, because the installed agent owns authentication,
/// provider selection, and any account-specific availability rules.
final class CLIModelCatalogService: CLIModelListing, @unchecked Sendable {
    private let resolver: CLIResolving
    private let runner: ProcessRunning
    private let timeout: TimeInterval
    private let fileManager: FileManager

    init(
        resolver: CLIResolving = CLIResolver(),
        runner: ProcessRunning = ProcessRunner(),
        timeout: TimeInterval = 15,
        fileManager: FileManager = .default
    ) {
        self.resolver = resolver
        self.runner = runner
        self.timeout = max(0.1, timeout)
        self.fileManager = fileManager
    }

    func models(for kind: CLIKind, executableOverride: String? = nil) async throws -> [CLIModel] {
        guard kind.supportsModelListing else {
            throw CLIModelListingError.unsupported(kind)
        }
        guard let executable = resolver.executableURL(for: kind, override: executableOverride) else {
            throw CLIModelListingError.executableNotFound(kind)
        }

        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("CapsStack-models-\(kind.rawValue)-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: temporaryDirectory) }

            let specification = ProcessSpecification(
                executableURL: executable,
                arguments: Self.arguments(for: kind),
                currentDirectoryURL: temporaryDirectory
            )
            let result: ProcessResult
            do {
                result = try await runner.run(specification, timeout: timeout)
            } catch ProcessRunnerError.timedOut {
                throw CLIModelListingError.timedOut(kind)
            } catch ProcessRunnerError.cancelled {
                throw CancellationError()
            } catch {
                throw CLIModelListingError.processFailed(kind)
            }

            guard result.succeeded else {
                throw CLIModelListingError.processFailed(kind)
            }
            guard !result.didTruncateOutput else {
                throw CLIModelListingError.invalidOutput(kind)
            }

            // Some CLIs write progress or provider warnings to stderr even when the catalog is
            // valid. The parser accepts both streams but never exposes their raw contents in an
            // error message, keeping credentials and provider diagnostics out of the UI.
            let models = CLIModelCatalogParser.parse(
                stdout: result.standardOutput,
                stderr: result.standardError,
                kind: kind
            )
            return models
        } catch let error as CLIModelListingError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw CLIModelListingError.processFailed(kind)
        }
    }

    private static func arguments(for kind: CLIKind) -> [String] {
        switch kind {
        case .codex:
            return ["debug", "models", "--bundled"]
        case .opencode:
            return ["models"]
        case .pi:
            return ["--list-models"]
        case .kiloCode:
            return ["models"]
        default:
            return []
        }
    }
}

enum CLIModelCatalogParser {
    /// Parses both JSON catalogs (when a CLI provides one) and the line-oriented output used by
    /// the current OpenCode, Pi, and Kilo Code commands.
    static func parse(stdout: Data, stderr: Data = Data(), kind: CLIKind) -> [CLIModel] {
        var models: [CLIModel] = []
        appendJSONModels(from: stdout, to: &models)

        // A few versions print a JSON object per line after a progress prefix. Trying each line
        // costs little and lets us tolerate that format without weakening the text parser.
        let stdoutText = String(decoding: stdout, as: UTF8.self)
        for line in stdoutText.split(whereSeparator: { $0.isNewline }) {
            if let data = String(line).data(using: .utf8) {
                appendJSONModels(from: data, to: &models)
            }
        }

        let text = stdoutText + "\n" + String(decoding: stderr, as: UTF8.self)
        appendTextModels(from: text, kind: kind, to: &models)
        return unique(models)
    }

    private static func appendJSONModels(from data: Data, to models: inout [CLIModel]) {
        let object: Any?
        if let parsed = try? JSONSerialization.jsonObject(with: data, options: []) {
            object = parsed
        } else if let text = String(data: data, encoding: .utf8),
                  let start = text.firstIndex(of: "{"),
                  let end = text.lastIndex(of: "}"),
                  start < end {
            object = try? JSONSerialization.jsonObject(
                with: Data(text[start...end].utf8),
                options: []
            )
        } else {
            object = nil
        }
        guard let object else { return }
        if let dictionary = object as? [String: Any] {
            if let values = dictionary["models"] as? [Any] {
                appendJSONValues(values, to: &models)
            } else if let values = dictionary["data"] as? [Any] {
                appendJSONValues(values, to: &models)
            }
        } else if let values = object as? [Any] {
            appendJSONValues(values, to: &models)
        }
    }

    private static func appendJSONValues(_ values: [Any], to models: inout [CLIModel]) {
        for value in values {
            if let id = value as? String {
                append(CLIModel(id: id), to: &models)
                continue
            }
            guard let dictionary = value as? [String: Any] else { continue }
            let id = ["slug", "id", "model", "name"]
                .compactMap { dictionary[$0] as? String }
                .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            guard let id else { continue }
            let displayName = (dictionary["display_name"] as? String)
                ?? (dictionary["displayName"] as? String)
                ?? (dictionary["name"] as? String)
            append(CLIModel(id: id, displayName: displayName), to: &models)
        }
    }

    private static func appendTextModels(from text: String, kind: CLIKind, to models: inout [CLIModel]) {
        let cleanedText = stripANSI(text)
        var piTableHeaderSeen = false
        for rawLine in cleanedText.split(whereSeparator: { $0.isNewline }) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if let data = line.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data, options: [])) != nil {
                continue
            }

            // Pi prints provider and model as separate columns, while --model accepts the
            // provider/model form used by the other provider-aware CLIs.
            if kind == .pi {
                let columns = line.split(whereSeparator: { $0.isWhitespace || "|•,".contains($0) })
                if columns.count >= 2 {
                    let provider = String(columns[0])
                    let model = String(columns[1])
                    let providerKey = provider.lowercased()
                    let modelKey = model.lowercased()
                    if providerKey == "provider", modelKey == "model" {
                        piTableHeaderSeen = true
                        continue
                    }
                    let ignoredPiColumns = Set([
                        "provider", "providers", "model", "models", "context", "max-out", "thinking",
                        "images", "yes", "no", "available", "loading"
                    ])
                    if piTableHeaderSeen,
                       !provider.contains("/"),
                       !ignoredPiColumns.contains(providerKey),
                       !ignoredPiColumns.contains(modelKey),
                       isPiColumnValue(model) {
                        let id = model.contains("/") ? model : "\(provider)/\(model)"
                        append(CLIModel(id: id), to: &models)
                        continue
                    }
                }
            }

            // Model IDs are the first field in the tabular output. Looking at each token also
            // tolerates a provider prefix or a trailing status marker.
            for rawToken in line.split(whereSeparator: { $0.isWhitespace || "|•,".contains($0) }) {
                let token = String(rawToken).trimmingCharacters(in: CharacterSet(charactersIn: "\"'`()[]{}:;"))
                guard isModelID(token, kind: kind) else { continue }
                append(CLIModel(id: token), to: &models)
            }
        }
    }

    private static func isPiColumnValue(_ value: String) -> Bool {
        guard value.count >= 1,
              !value.hasPrefix("-"),
              !value.contains(where: { "{}[]\"'()=\\".contains($0) }),
              value.rangeOfCharacter(from: .letters) != nil || value.rangeOfCharacter(from: .decimalDigits) != nil
        else {
            return false
        }
        return true
    }

    private static func isModelID(_ value: String, kind: CLIKind) -> Bool {
        guard value.count >= 2,
              !value.hasPrefix("-"),
              !value.contains("="),
              !value.contains("\\"),
              !value.contains(where: { "{}[]\"".contains($0) }),
              !value.hasPrefix("/"),
              !value.hasPrefix("./"),
              !value.hasPrefix("http") else {
            return false
        }

        let lowercased = value.lowercased()
        let ignored = Set([
            "model", "models", "modelid", "provider", "string", "name", "id", "auto",
            "true", "false", "default", "available", "list", "all", "help", "optional"
        ])
        if ignored.contains(lowercased) {
            return false
        }

        if kind == .opencode || kind == .kiloCode || kind == .pi {
            return value.contains("/") && value.split(separator: "/").count >= 2
        }

        // Codex's fallback text output is intentionally conservative: model IDs conventionally
        // contain a digit or one of the well-known provider/model family prefixes. This avoids
        // turning ordinary status words into selectable models.
        let prefixes = [
            "gpt", "o1", "o3", "o4", "claude", "sonnet", "opus", "haiku", "gemini", "codex",
            "qwen", "deepseek", "mistral", "llama", "grok", "kimi", "command", "nova", "gemma",
            "phi", "minimax"
        ]
        if prefixes.contains(where: { lowercased.hasPrefix($0) }) {
            return true
        }
        return kind == .codex
            && value.rangeOfCharacter(from: .decimalDigits) != nil
            && (value.contains("-") || value.contains(".") || value.contains("/"))
    }

    private static func append(_ model: CLIModel, to models: inout [CLIModel]) {
        guard !model.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        models.append(model)
    }

    private static func unique(_ models: [CLIModel]) -> [CLIModel] {
        var seen = Set<String>()
        return models.filter { model in
            seen.insert(model.id).inserted
        }
    }

    private static func stripANSI(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "\\u{001B}\\[[0-?]*[ -/]*[@-~]",
            options: []
        ) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }
}
