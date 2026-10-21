// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DeepSeekBalanceIndicator",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "DeepSeekBalanceIndicator",
            path: "Sources/DeepSeekBalanceIndicator",
            resources: [.copy("Resources")]
        )
    ]
)
