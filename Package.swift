// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DeskBuddy",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DeskBuddy", targets: ["DeskBuddy"])
    ],
    targets: [
        .executableTarget(
            name: "DeskBuddy",
            resources: [.process("Resources")]
        )
    ]
)
