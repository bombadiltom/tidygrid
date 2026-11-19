// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TidyGrid",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "TidyGrid", path: "Sources/TidyGrid")
    ]
)
