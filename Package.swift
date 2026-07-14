// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SMKConfigurator",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/stackotter/swift-cross-ui", .upToNextMinor(from: "0.8.0"))
    ],
    targets: [
        .executableTarget(
            name: "SMKConfigurator",
            dependencies: [
                .product(name: "SwiftCrossUI", package: "swift-cross-ui"),
                .product(name: "DefaultBackend", package: "swift-cross-ui"),
            ]
        ),
        .testTarget(
            name: "SMKConfiguratorTests",
            dependencies: ["SMKConfigurator"]
        ),
    ]
)
