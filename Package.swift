// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Sidekick",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Sidekick", targets: ["Sidekick"]),
    ],
    targets: [
        .target(name: "SidekickCore"),
        .executableTarget(name: "Sidekick", dependencies: ["SidekickCore"]),
        .testTarget(name: "SidekickCoreTests", dependencies: ["SidekickCore"]),
    ]
)
