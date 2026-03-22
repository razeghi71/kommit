// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Domino",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "DominoKit",
            path: "Sources/DominoKit"
        ),
        .executableTarget(
            name: "Domino",
            dependencies: ["DominoKit"],
            path: "Sources/Domino",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "DominoTests",
            dependencies: ["DominoKit"],
            path: "Tests/DominoTests"
        ),
    ]
)
