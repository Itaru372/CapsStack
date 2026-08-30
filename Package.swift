// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CapsStack",
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
        .package(url: "https://github.com/PostHog/posthog-ios.git", exact: "3.69.5")
    ],
    targets: [
        .executableTarget(
            name: "CapsStack",
            dependencies: [
                .product(name: "PostHog", package: "posthog-ios")
            ],
            path: "Sources/CapsStack",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "CapsStackCLI",
            path: "Sources/CapsStackCLI"
        ),
        .testTarget(
            name: "CapsStackTests",
            dependencies: ["CapsStack"],
            path: "Tests/CapsStackTests"
        ),
        .testTarget(
            name: "CapsStackCLITests",
            dependencies: ["CapsStackCLI"],
            path: "Tests/CapsStackCLITests"
        )
    ],
    swiftLanguageModes: [.v5]
)
