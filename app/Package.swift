// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SharpFocus",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SharpFocus",
            path: "Sources/SharpFocus",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "sfctl",
            path: "Sources/sfctl"
        ),
    ]
)
