// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Vigil",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Vigil",
            path: "Sources"
        ),
    ]
)
