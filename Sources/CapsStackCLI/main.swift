import Foundation

private func write(_ text: String, to handle: FileHandle) {
    guard !text.isEmpty else { return }
    let terminated = text.hasSuffix("\n") ? text : text + "\n"
    handle.write(Data(terminated.utf8))
}

let result = CapsStackCLIApplication().run(arguments: Array(CommandLine.arguments.dropFirst()))
write(result.stdout, to: .standardOutput)
write(result.stderr, to: .standardError)
exit(result.exitCode)
