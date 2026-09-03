import Foundation

protocol GUIAppDetecting: Sendable {
    func isInstalled(bundleIdentifier: String) -> Bool
}

/// Detects supported desktop clients by bundle identifier without launching them or asking for
/// Accessibility/Screen Recording permissions.
struct GUIAppDetector: GUIAppDetecting, @unchecked Sendable {
    private let fileManager: FileManager
    private let applicationDirectories: [URL]

    init(
        fileManager: FileManager = .default,
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        applicationDirectories: [URL]? = nil
    ) {
        self.fileManager = fileManager
        self.applicationDirectories = applicationDirectories ?? [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            homeDirectory.appendingPathComponent("Applications", isDirectory: true)
        ]
    }

    func isInstalled(bundleIdentifier: String) -> Bool {
        for directory in applicationDirectories {
            guard let applications = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for application in applications where application.pathExtension.lowercased() == "app" {
                guard let bundle = Bundle(url: application) else { continue }
                if bundle.bundleIdentifier == bundleIdentifier { return true }
            }
        }
        return false
    }
}
