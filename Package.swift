// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CapsStack",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CapsStack", targets: ["CapsStack"])
    ],
    targets: [
        .executableTarget(
            name: "CapsStack",
            path: "Sources/CapsStack",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "CapsStackTests",
            dependencies: ["CapsStack"],
            path: "Tests/CapsStackTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
