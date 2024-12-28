// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Rekal",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Rekal")
    ]
)
