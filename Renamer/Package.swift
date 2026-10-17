// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Renamer",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "RenamerFeature", targets: ["RenamerFeature"]),
        .executable(name: "Renamer", targets: ["Renamer"])
    ],
    dependencies: [
        .package(path: "../RenamerCore")
    ],
    targets: [
        .target(name: "RenamerFeature", dependencies: ["RenamerCore"], path: "Sources/RenamerFeature"),
        .executableTarget(name: "Renamer", dependencies: ["RenamerFeature"], path: "Sources/Renamer")
    ]
)
