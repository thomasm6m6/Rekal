// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Rekal",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", .upToNextMinor(from: "0.15.3")),
        .package(url: "https://github.com/apple/swift-collections.git", .upToNextMinor(from: "1.1.0"))
    ],
    targets: [
        .target(
            name: "Common",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift")
            ]
            // path: "Sources/Common"
        ),
        .executableTarget(
            name: "rekald",
            dependencies: [
                "Common",
                .product(name: "Collections", package: "swift-collections")
            ]
            // path: "Sources/rekald"
        ),
        .executableTarget(
            name: "rekal",
            dependencies: ["Common"]
            // path: "Sources/rekal"
        )
    ]
)