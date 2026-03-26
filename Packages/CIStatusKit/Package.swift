// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CIStatusKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CIStatusKit", targets: ["CIStatusKit"]),
    ],
    dependencies: [
        .package(path: "../GitHubKit"),
    ],
    targets: [
        .target(name: "CIStatusKit", dependencies: ["GitHubKit"]),
        .testTarget(name: "CIStatusKitTests", dependencies: ["CIStatusKit"]),
    ]
)
