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
    targets: [
        .executableTarget(
            name: "CapsStack",
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
