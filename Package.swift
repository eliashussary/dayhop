// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Dayhop",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Dayhop", path: "Sources/Dayhop")
    ],
    swiftLanguageModes: [.v5]
)
