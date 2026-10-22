// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Keypsake",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Keypsake", path: "Sources/Keypsake")
    ]
)
