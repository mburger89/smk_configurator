// swift-tools-version: 6.2
import PackageDescription

// One source tree, `Sources/SMKConfigurator/`, declared as one target named
// `SMKConfigurator` per platform (port plan §4.1):
//
// - **macOS**: the app — an executable over `Model/`, `Device/`, `Views/` and
//   `main.swift`, drawn by MetalUI (AppKit + Metal).
// - **Linux, Windows**: a library over `Model/` and `Device/` only, with no UI
//   dependency at all — MetalUI is not even declared there. Those builds are
//   what enforces "the model has no UI type": a `Model/` file that imports
//   MetalUI or names a view fails to compile on Linux and Windows CI. The UI
//   on Linux and Windows (MetalUI's `Backends/SDL`) is a later, separate item.
//
// A separate UI-free library target was the preferred shape and is ruled out
// by the code: a second module only sees `public`/`package` declarations, and
// two generated files (`Model/KeyCodesGenerated.swift`,
// `Device/BLEUploadUUIDs.swift`, emitted by scripts in the firmware repo) carry
// no access modifiers and must stay byte-identical to the firmware's copies.

// Each platform's icons live under `Resources/<Platform>/Icons/` so `.copy()`
// -- which keeps only the basename ("Icons") -- lands them at the same in-bundle
// path, `Icons/<light|dark>/<icon>.png` (see `Views/IconLoader.swift`). Only the
// macOS app draws icons; the other two trees stay in the repo for the later
// Linux/Windows UI and are excluded here.
let allPlatformIconPaths = [
    "Resources/macOS/Icons",
    "Resources/Windows/Icons",
    "Resources/Linux/Icons",
]

let hidapiLinkerSettings: [LinkerSetting] = [
    .linkedFramework("CoreBluetooth", .when(platforms: [.macOS])),
    // pkgConfig: "hidapi" resolves fully on macOS (Homebrew ships a unified
    // hidapi.pc with both Cflags and Libs), but Ubuntu's libhidapi-dev has no
    // plain hidapi.pc -- only hidapi-hidraw.pc/hidapi-libusb.pc -- so link
    // explicitly per platform.
    .linkedLibrary("hidapi", .when(platforms: [.macOS])),
    .linkedLibrary("hidapi-hidraw", .when(platforms: [.linux])),
    // vcpkg's hidapi port on Windows produces hidapi.lib.
    .linkedLibrary("hidapi", .when(platforms: [.windows])),
]

let chidapi = Target.systemLibrary(
    name: "CHidapi",
    pkgConfig: "hidapi",
    providers: [
        .brew(["hidapi"]),
        .apt(["libhidapi-dev"]),
    ]
)

#if os(macOS)
let package = Package(
    name: "SMKConfigurator",
    platforms: [.macOS(.v26)],
    dependencies: [
        // Pinned to one commit, as `metalui new` pins it (MetalUI ruling SC-I).
        // Move the pin deliberately: a newer `revision:`, then `swift package update`.
        .package(url: "https://github.com/mburger89/MetalUI", revision: "e54c3f65086b446d42b09bf6f2fdbf802f7ed52a"),
    ],
    targets: [
        chidapi,
        .executableTarget(
            name: "SMKConfigurator",
            dependencies: [
                .product(name: "MetalUI", package: "MetalUI"),
                "CHidapi",
            ],
            exclude: allPlatformIconPaths.filter { $0 != "Resources/macOS/Icons" },
            resources: [.copy("Resources/macOS/Icons")],
            linkerSettings: hidapiLinkerSettings
        ),
        .testTarget(
            name: "SMKConfiguratorTests",
            dependencies: [
                "SMKConfigurator",
                .product(name: "MetalUI", package: "MetalUI"),
                // A `TextSystem` a test can construct, so `renderFrame` can
                // build a frame with no window (ShellRenderTests).
                .product(name: "MetalUIPortableText", package: "MetalUI"),
                .product(name: "MetalUISystemFonts", package: "MetalUI"),
            ]
        ),
    ]
)
#else
let package = Package(
    name: "SMKConfigurator",
    dependencies: [],
    targets: [
        chidapi,
        .target(
            name: "SMKConfigurator",
            dependencies: ["CHidapi"],
            exclude: ["Views", "main.swift", "Resources"],
            linkerSettings: hidapiLinkerSettings
        ),
        .testTarget(
            name: "SMKConfiguratorTests",
            dependencies: ["SMKConfigurator"],
            // These import MetalUI, which is not declared here, or test types
            // under `Views/`, which this target excludes: macOS only.
            // IconLoaderTests also needs the bundled PNGs; ShellRenderTests and
            // PaneRenderTests draw; PaneLogicTests tests view-level helpers.
            // Any later test file importing MetalUI or naming a view type joins
            // this list.
            exclude: ["IconLoaderTests.swift", "ShellRenderTests.swift",
                      "PaneRenderTests.swift", "PaneLogicTests.swift"]
        ),
    ]
)
#endif
