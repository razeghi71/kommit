// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Kommit",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "KommitKit",
            path: "Sources/KommitKit"
        ),
        .executableTarget(
            name: "Kommit",
            dependencies: ["KommitKit"],
            path: "Sources/Kommit",
            resources: [.process("Resources")]
        ),
    ]
)
