// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "MarkletCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MarkletCore", targets: ["MarkletCore"])],
    targets: [
        .target(name: "MarkletCore"),
        .testTarget(name: "MarkletCoreTests", dependencies: ["MarkletCore"])
    ]
)
