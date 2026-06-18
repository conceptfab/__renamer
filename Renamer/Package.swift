// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Renamer",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "../RenamerCore")
    ],
    targets: [
        .executableTarget(
            name: "Renamer",
            dependencies: ["RenamerCore"],
            path: "Sources/Renamer"
        )
    ]
)
