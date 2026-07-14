// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "mac-token-plan",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "mac-token-plan",
            path: "Sources"
        )
    ]
)
