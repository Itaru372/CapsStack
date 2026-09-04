import CapsStackLocalization
import Foundation

enum CLICommand: Equatable {
    case help
    case version
    case status(json: Bool)
    case historyList(limit: Int?, json: Bool)
    case historyLatest(mode: CLIOutputMode)
    case historyShow(id: UUID, mode: CLIOutputMode)
    case memoGet(json: Bool)
    case memoSet(text: String?, stdin: Bool, json: Bool)
    case memoClear(json: Bool)
}

enum CLIArgumentError: LocalizedError, Equatable {
    case unknownCommand(String)
    case missingArgument(String)
    case invalidArgument(String)
    case conflictingOptions(String)

    var errorDescription: String? {
        switch self {
        case .unknownCommand(let command): CapsStackText.format(.unknownCommand, command)
        case .missingArgument(let argument): CapsStackText.format(.missingArgument, argument)
        case .invalidArgument(let argument): CapsStackText.format(.invalidArgument, argument)
        case .conflictingOptions(let options): CapsStackText.format(.conflictingOptions, options)
        }
    }
}

enum CLIArgumentParser {
    static func parse(_ arguments: [String]) throws -> CLICommand {
        guard let first = arguments.first else { return .help }
        if first == "--help" || first == "-h" { return .help }
        if first == "--version" || first == "-V" { return .version }

        switch first {
        case "help":
            guard arguments.count == 1 else { throw CLIArgumentError.invalidArgument(arguments[1]) }
            return .help
        case "version":
            guard arguments.count == 1 else { throw CLIArgumentError.invalidArgument(arguments[1]) }
            return .version
        case "status":
            return .status(json: try parseJSONOnly(Array(arguments.dropFirst())))
        case "history":
            return try parseHistory(Array(arguments.dropFirst()))
        case "memo":
            return try parseMemo(Array(arguments.dropFirst()))
        default:
            throw CLIArgumentError.unknownCommand(first)
        }
    }

    private static func parseHistory(_ arguments: [String]) throws -> CLICommand {
        guard let action = arguments.first else {
            throw CLIArgumentError.missingArgument(CapsStackText.resolve(.historyActions))
        }
        let rest = Array(arguments.dropFirst())
        switch action {
        case "list":
            var limit: Int?
            var json = false
            var index = 0
            while index < rest.count {
                switch rest[index] {
                case "--json":
                    json = true
                    index += 1
                case "--limit":
                    guard index + 1 < rest.count else {
                        throw CLIArgumentError.missingArgument("--limit N")
                    }
                    guard let parsed = Int(rest[index + 1]), parsed > 0 else {
                        throw CLIArgumentError.invalidArgument("--limit \(rest[index + 1])")
                    }
                    limit = parsed
                    index += 2
                default:
                    throw CLIArgumentError.invalidArgument(rest[index])
                }
            }
            return .historyList(limit: limit, json: json)
        case "latest":
            return .historyLatest(mode: try parseOutputMode(rest))
        case "show":
            guard let rawID = rest.first else { throw CLIArgumentError.missingArgument("<UUID>") }
            guard let id = UUID(uuidString: rawID) else { throw CLIArgumentError.invalidArgument(rawID) }
            return .historyShow(id: id, mode: try parseOutputMode(Array(rest.dropFirst())))
        default:
            throw CLIArgumentError.unknownCommand("history \(action)")
        }
    }

    private static func parseMemo(_ arguments: [String]) throws -> CLICommand {
        guard let action = arguments.first else {
            throw CLIArgumentError.missingArgument(CapsStackText.resolve(.memoActions))
        }
        let rest = Array(arguments.dropFirst())
        switch action {
        case "get":
            return .memoGet(json: try parseJSONOnly(rest))
        case "clear":
            return .memoClear(json: try parseJSONOnly(rest))
        case "set":
            var json = false
            var stdin = false
            var textParts: [String] = []
            for argument in rest {
                switch argument {
                case "--json": json = true
                case "--stdin": stdin = true
                default:
                    if argument.hasPrefix("--") { throw CLIArgumentError.invalidArgument(argument) }
                    textParts.append(argument)
                }
            }
            if stdin && !textParts.isEmpty {
                throw CLIArgumentError.conflictingOptions(CapsStackText.resolve(.stdinAndText))
            }
            if !stdin && textParts.isEmpty {
                throw CLIArgumentError.missingArgument(CapsStackText.resolve(.textOrStdin))
            }
            return .memoSet(text: textParts.isEmpty ? nil : textParts.joined(separator: " "), stdin: stdin, json: json)
        default:
            throw CLIArgumentError.unknownCommand("memo \(action)")
        }
    }

    private static func parseJSONOnly(_ arguments: [String]) throws -> Bool {
        var json = false
        for argument in arguments {
            guard argument == "--json" else { throw CLIArgumentError.invalidArgument(argument) }
            guard !json else { throw CLIArgumentError.invalidArgument(argument) }
            json = true
        }
        return json
    }

    private static func parseOutputMode(_ arguments: [String]) throws -> CLIOutputMode {
        var mode = CLIOutputMode.human
        for argument in arguments {
            let requested: CLIOutputMode
            switch argument {
            case "--json": requested = .json
            case "--markdown": requested = .markdown
            default: throw CLIArgumentError.invalidArgument(argument)
            }
            guard mode == .human else {
                throw CLIArgumentError.conflictingOptions(CapsStackText.resolve(.jsonAndMarkdown))
            }
            mode = requested
        }
        return mode
    }
}
