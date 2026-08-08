// swift-tools-version: 6.0
import PackageDescription

// SF Symbols are only ever bundled into the macOS build (see the
// platform-native-icons design spec's Global Constraint). `Resource.copy()`
// has no `.when(platforms:)` overload, and Swift doesn't allow `#if` inside
// an array literal, so the platform subtree is selected here via a
// top-level `#if os(...)`-gated variable instead -- this file is a Swift
// script evaluated at build time on the host, and each platform builds
// natively (macOS builds compile on macOS, Windows on Windows, Linux on
// Linux), so this picks only that platform's icons.
//
// Each platform's icons live under `Resources/<Platform>/Icons/` (rather
// than `Resources/Icons/<Platform>/`) so that `.copy()` -- which preserves
// only the resource's basename ("Icons") as the top-level folder in the
// built resource bundle -- lands every platform's assets at the same
// in-bundle path, `Icons/<light|dark>/<icon>.png`. See `IconLoader` in
// `Views/AppIcon.swift`.
#if os(macOS)
let iconResources: [Resource] = [.copy("Resources/macOS/Icons")]
let unusedIconPaths = ["Resources/Windows/Icons", "Resources/Linux/Icons"]
#elseif os(Windows)
let iconResources: [Resource] = [.copy("Resources/Windows/Icons")]
let unusedIconPaths = ["Resources/macOS/Icons", "Resources/Linux/Icons"]
#else
let iconResources: [Resource] = [.copy("Resources/Linux/Icons")]
let unusedIconPaths = ["Resources/macOS/Icons", "Resources/Windows/Icons"]
#endif

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
            exclude: unusedIconPaths,
            resources: iconResources,
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
                // vcpkg's hidapi port on Windows produces hidapi.lib, no
                // per-backend split like Linux — unverified until CI runs,
                // per this repo's established pattern of iterating against
                // real CI output rather than guessing further.
                .linkedLibrary("hidapi", .when(platforms: [.windows])),
            ]
        ),
        .testTarget(
            name: "SMKConfiguratorTests",
            dependencies: ["SMKConfigurator"]
        ),
    ]
)
