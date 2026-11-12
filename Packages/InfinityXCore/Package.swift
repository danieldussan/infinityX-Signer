// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "InfinityXCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "InfinityXCore", targets: ["InfinityXCore"])],
    targets: [
        .target(name: "InfinityXCore"),
        .testTarget(name: "InfinityXCoreTests", dependencies: ["InfinityXCore"]),
    ]
)
