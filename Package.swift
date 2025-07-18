// swift-tools-version: 6.1
import PackageDescription

let package = Package(
  name: "rekal",
  platforms: [.macOS(.v15)],
  dependencies: [
    .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.4")
  ],
  targets: [
    .executableTarget(
      name: "rekal",
      dependencies: [
        .product(name: "SQLite", package: "SQLite.swift")
      ])
  ]
)
