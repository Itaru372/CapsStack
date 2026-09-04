// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CapsStack",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CapsStack", targets: ["CapsStack"]),
        // `CapsStack` and `capsstack` collide on the default case-insensitive macOS filesystem.
        // The packaged binary is installed as `Contents/Helpers/capsstack`.
        .executable(name: "capsstack-cli", targets: ["CapsStackCLI"])
    ],
    dependencies: [
        // PostHog's native Swift SDK supports macOS and is used only through the
        // privacy-reviewed TelemetryClient adapter.
        .package(url: "https://github.com/PostHog/posthog-ios.git", exact: "3.69.5"),
        // Copilot stores workspace metadata as YAML. Use its maintained parser instead of
        // interpreting scalar syntax ourselves.
        .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2")
    ],
    targets: [
        .executableTarget(
            name: "CapsStack",
            dependencies: [
                "CapsStackLocalization",
                .product(name: "PostHog", package: "posthog-ios"),
                .product(name: "Yams", package: "Yams")
            ],
            path: "Sources/CapsStack",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "CapsStackCLI",
            dependencies: ["CapsStackLocalization"],
            path: "Sources/CapsStackCLI"
        ),
        .target(
            name: "CapsStackLocalization",
            path: "Sources/CapsStackLocalization",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "CapsStackTests",
            dependencies: ["CapsStack", "CapsStackLocalization"],
            path: "Tests/CapsStackTests"
        ),
        .testTarget(
            name: "CapsStackCLITests",
            dependencies: ["CapsStackCLI", "CapsStackLocalization"],
            path: "Tests/CapsStackCLITests"
        )
    ],
    swiftLanguageModes: [.v5]
)
