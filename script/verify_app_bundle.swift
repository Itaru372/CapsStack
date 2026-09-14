import AppKit
import Darwin
import Foundation

func fail(_ message: String) -> Never {
    let output = "CapsStack bundle verification failed: \(message)\n"
    FileHandle.standardError.write(Data(output.utf8))
    exit(EXIT_FAILURE)
}

func require(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String) {
    if !condition() {
        fail(message())
    }
}

func resourceBundle(
    named name: String,
    in resourcesURL: URL
) -> Bundle {
    let url = resourcesURL.appendingPathComponent(name, isDirectory: true)
    require(
        FileManager.default.fileExists(atPath: url.path),
        "missing resource bundle: \(url.path)"
    )
    guard let bundle = Bundle(url: url) else {
        fail("could not load resource bundle: \(url.path)")
    }
    return bundle
}

guard CommandLine.arguments.count == 2 else {
    fail("usage: verify_app_bundle.swift /path/to/CapsStack.app")
}

let appURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
require(appURL.pathExtension == "app", "expected a .app bundle: \(appURL.path)")
require(
    FileManager.default.fileExists(atPath: appURL.path),
    "app bundle does not exist: \(appURL.path)"
)

guard let appBundle = Bundle(url: appURL) else {
    fail("could not load app bundle: \(appURL.path)")
}
guard let resourcesURL = appBundle.resourceURL else {
    fail("app bundle has no Contents/Resources directory: \(appURL.path)")
}

let info = appBundle.infoDictionary ?? [:]
require(info["CFBundleExecutable"] as? String == "CapsStack", "unexpected app executable")
require(info["CFBundleIdentifier"] as? String == "com.capsstack.CapsStack", "unexpected bundle identifier")
require(info["CFBundlePackageType"] as? String == "APPL", "unexpected bundle package type")

let localizations = Set(info["CFBundleLocalizations"] as? [String] ?? [])
require(localizations.contains("en"), "English localization is not declared")
require(localizations.contains("ja"), "Japanese localization is not declared")

let brandBundle = resourceBundle(named: "CapsStack_CapsStack.bundle", in: resourcesURL)
let artworkResources = [
    (name: "AgentCodex", fileExtension: "svg"),
    (name: "AgentClaudeCode", fileExtension: "svg"),
    (name: "AgentOpenCode", fileExtension: "svg"),
    (name: "AgentPi", fileExtension: "svg"),
    (name: "AgentGitHubCopilot", fileExtension: "svg"),
    (name: "AgentKilo", fileExtension: "png"),
    (name: "AgentGoose", fileExtension: "png"),
    (name: "AgentQwen", fileExtension: "png"),
    (name: "AgentContinue", fileExtension: "png"),
    (name: "AgentGemini", fileExtension: "png")
]
for artwork in artworkResources {
    guard let imageURL = brandBundle.url(
        forResource: artwork.name,
        withExtension: artwork.fileExtension
    ) else {
        fail("missing agent artwork: \(artwork.name).\(artwork.fileExtension)")
    }
    guard let image = NSImage(contentsOf: imageURL), image.isValid,
          image.size.width > 0, image.size.height > 0 else {
        fail("agent artwork could not be decoded: \(imageURL.path)")
    }
}

for name in ["CapsStackAppIcon", "CapsStackMenuBar"] {
    guard let imageURL = brandBundle.url(forResource: name, withExtension: "png"),
          let image = NSImage(contentsOf: imageURL), image.isValid,
          image.size.width > 0, image.size.height > 0 else {
        fail("brand artwork could not be decoded: \(name).png")
    }
}

let localizationBundle = resourceBundle(
    named: "CapsStack_CapsStackLocalization.bundle",
    in: resourcesURL
)
for language in ["en", "ja"] {
    guard let languagePath = localizationBundle.path(forResource: language, ofType: "lproj"),
          let languageBundle = Bundle(path: languagePath),
          languageBundle.path(forResource: "Localizable", ofType: "strings") != nil else {
        fail("missing Localizable.strings for \(language)")
    }
}

guard let japanesePath = localizationBundle.path(forResource: "ja", ofType: "lproj"),
      let japaneseBundle = Bundle(path: japanesePath) else {
    fail("could not load Japanese localization bundle")
}

let expectedJapanese: [String: String] = [
    "History": "履歴",
    "Settings": "設定",
    "What matters now": "いま把握すべきこと",
    "Session details": "セッションの詳細",
    "Next action": "次の一手",
    "Waiting": "確認待ち",
    "Problem": "問題",
    "Decision": "決定",
    "Discovery": "発見",
    "Verified": "検証済み",
    "Risk": "リスク",
    "Change": "変更"
]
for (key, expected) in expectedJapanese {
    let value = japaneseBundle.localizedString(
        forKey: key,
        value: "__CAPSSTACK_MISSING__",
        table: "Localizable"
    )
    require(value == expected, "Japanese localization mismatch for \(key): \(value)")
}

let postHogBundles = [
    "PostHog_PostHog.bundle",
    "PostHog_PHPLCrashReporter.bundle"
]
for name in postHogBundles {
    let bundle = resourceBundle(named: name, in: resourcesURL)
    guard let privacyURL = bundle.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
          let privacyData = try? Data(contentsOf: privacyURL),
          let propertyList = try? PropertyListSerialization.propertyList(
              from: privacyData,
              options: [],
              format: nil
          ),
          propertyList is [String: Any] else {
        fail("PostHog privacy manifest could not be loaded: \(name)")
    }
}

let helperURL = appURL
    .appendingPathComponent("Contents", isDirectory: true)
    .appendingPathComponent("Helpers", isDirectory: true)
    .appendingPathComponent("capsstack", isDirectory: false)
require(
    FileManager.default.isExecutableFile(atPath: helperURL.path),
    "packaged CLI helper is missing or not executable"
)

print("Verified CapsStack.app bundle: \(appURL.path)")
