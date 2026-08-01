// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SMKConfigurator",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/stackotter/swift-cross-ui", .upToNextMinor(from: "0.8.0"))
    ],
    targets: [
        .systemLibrary(
            name: "CHidapi",
            pkgConfig: "hidapi",
            providers: [
                .brew(["hidapi"]),
                .apt(["libhidapi-dev"]),
            ]
        ),
        .executableTarget(
            name: "SMKConfigurator",
            dependencies: [
                .product(name: "SwiftCrossUI", package: "swift-cross-ui"),
                .product(name: "DefaultBackend", package: "swift-cross-ui"),
                "CHidapi",
            ],
            linkerSettings: [
                .linkedFramework("CoreBluetooth", .when(platforms: [.macOS])),
            ]
        ),
        .testTarget(
            name: "SMKConfiguratorTests",
            dependencies: ["SMKConfigurator"]
        ),
    ]
)
