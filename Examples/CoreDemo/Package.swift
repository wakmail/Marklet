// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "CoreDemo",
    platforms: [.macOS(.v14)],
    dependencies: [.package(name: "MarkletCore", path: "../..")],
    targets: [.executableTarget(name: "CoreDemo", dependencies: [
        .product(name: "MarkletCore", package: "MarkletCore")
    ])]
)
