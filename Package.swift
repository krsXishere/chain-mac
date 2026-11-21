// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChainMac",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "ScrollCore"),
        .executableTarget(name: "ChainMac", dependencies: ["ScrollCore"], path: "Sources/ChainMac"),
        .testTarget(name: "ScrollCoreTests", dependencies: ["ScrollCore"]),
    ]
)
