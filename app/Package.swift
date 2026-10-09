// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "KhaledCLIHQ",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "KhaledCLIHQ", path: "Sources/KhaledCLIHQ")
    ],
    swiftLanguageModes: [.v5]
)
