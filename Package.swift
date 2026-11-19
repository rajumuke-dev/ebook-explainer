// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EbookExplainer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "EbookExplainer"),
        .testTarget(name: "EbookExplainerTests", dependencies: ["EbookExplainer"]),
    ]
)
