// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UsageKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "UsageKit", targets: ["UsageKit"]),
        .library(name: "UsageViews", targets: ["UsageViews"]),
    ],
    targets: [
        .target(name: "UsageKit"),
        .target(name: "UsageViews", dependencies: ["UsageKit"]),
        .testTarget(name: "UsageKitTests", dependencies: ["UsageKit"]),
    ]
)
