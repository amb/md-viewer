// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MDView", platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.9.0")],
    targets: [
        .executableTarget(name: "MDView", dependencies: [.product(name: "Markdown", package: "swift-markdown")]),
        .executableTarget(name: "MermaidWorker"),
        .testTarget(name: "MDViewTests", dependencies: ["MDView"])
    ], swiftLanguageModes: [.v5]
)
