// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RenamerCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "RenamerCore", targets: ["RenamerCore"])
    ],
    targets: [
        .target(name: "RenamerCore"),
        .testTarget(name: "RenamerCoreTests", dependencies: ["RenamerCore"])
    ]
)
