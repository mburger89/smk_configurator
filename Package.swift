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
                // pkgConfig: "hidapi" above resolves fully on macOS (Homebrew
                // ships a unified hidapi.pc with both Cflags and Libs), but
                // Ubuntu's libhidapi-dev has no plain hidapi.pc — only
                // hidapi-hidraw.pc/hidapi-libusb.pc — so pkgConfig silently
                // finds nothing there and no -l flag gets added. Link
                // explicitly per platform instead of relying on pkgConfig's
                // Libs: output for Linux.
                .linkedLibrary("hidapi", .when(platforms: [.macOS])),
                .linkedLibrary("hidapi-hidraw", .when(platforms: [.linux])),
            ]
        ),
        .testTarget(
            name: "SMKConfiguratorTests",
            dependencies: ["SMKConfigurator"]
        ),
    ]
)
