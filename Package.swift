// swift-tools-version: 6.2
import PackageDescription

// One source tree, `Sources/SMKConfigurator/`, declared as one target named
// `SMKConfigurator` (port plan §4.1; cross-platform plan §2.1):
//
// - **Default, every platform**: the app -- an executable over `Model/`,
//   `Device/`, `Views/` and `main.swift`, drawn by MetalUI. On macOS that is
//   AppKit + Metal; on Linux and Windows it is MetalUI's SDL backend
//   (`MetalUISDL`, behind MetalUI's `SDL` and `AccessKit` traits) with the
//   portable text system over the platform's fonts.
// - **`SMK_UI_FREE=1`, any platform**: a library over `Model/` and `Device/`
//   only, with no UI dependency at all -- MetalUI is not even declared. That
//   build is what enforces "the model has no UI type": a `Model/` or
//   `Device/` file that imports MetalUI or names a view fails
//   `SMK_UI_FREE=1 swift build --build-tests`. CI runs it on Linux and
//   Windows with its own `--scratch-path`.
//
// A separate UI-free library target was the preferred shape and is ruled out
// by the code: a second module only sees `public`/`package` declarations, and
// two generated files (`Model/KeyCodesGenerated.swift`,
// `Device/BLEUploadUUIDs.swift`, emitted by scripts in the firmware repo) carry
// no access modifiers and must stay byte-identical to the firmware's copies.

/// Model/ and Device/ alone, no UI dependency declared (plan §2.1).
let uiFree = Context.environment["SMK_UI_FREE"] == "1"

// Each platform's icons live under `Resources/<Platform>/Icons/` so `.copy()`
// -- which keeps only the basename ("Icons") -- lands them at the same in-bundle
// path, `Icons/<light|dark>/<icon>.png` (see `Views/IconLoader.swift`). Each
// platform bundles only its own tree: the SF Symbols licence keeps the macOS
// PNGs off every other platform (THIRD-PARTY-NOTICES.md).
let allPlatformIconPaths = [
    "Resources/macOS/Icons",
    "Resources/Windows/Icons",
    "Resources/Linux/Icons",
]

// MetalUI's SDL backend is compiled only when its `SDL` trait is on -- here,
// on Linux and Windows; `AccessKit` is its screen-reader bridge. macOS uses
// AppKit and needs neither (MetalUI rulings PX-H, PX-J; the shape
// `metalui new --cross-platform` generates).
#if os(macOS)
let iconTree = "Resources/macOS/Icons"
let metalUITraits: Set<Package.Dependency.Trait> = [.defaults]
#elseif os(Windows)
let iconTree = "Resources/Windows/Icons"
let metalUITraits: Set<Package.Dependency.Trait> = ["SDL", "AccessKit"]
#else
let iconTree = "Resources/Linux/Icons"
let metalUITraits: Set<Package.Dependency.Trait> = ["SDL", "AccessKit"]
#endif

let portable = TargetDependencyCondition.when(platforms: [.linux, .windows])

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

let package: Package

if uiFree {
    package = Package(
        name: "SMKConfigurator",
        platforms: [.macOS(.v26)],
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
                // These import MetalUI, which is not declared here, or test
                // types under `Views/`, which this target excludes.
                // IconLoaderTests also needs the bundled PNGs; ShellRenderTests,
                // SDLWindowTests and PaneRenderTests draw; PaneLogicTests tests
                // view-level helpers; MacroPaneTests does both for MACROS mode;
                // PlatformChromeTests drives a window through a fake platform.
                // Any later test file importing MetalUI or naming a view type
                // joins this list.
                exclude: ["IconLoaderTests.swift", "ShellRenderTests.swift",
                          "SDLWindowTests.swift", "PaneRenderTests.swift",
                          "PaneLogicTests.swift", "MacroPaneTests.swift",
                          "PlatformChromeTests.swift"]
            ),
        ]
    )
} else {
    package = Package(
        name: "SMKConfigurator",
        platforms: [.macOS(.v26)],
        dependencies: [
            // Pinned to one commit, as `metalui new` pins it (MetalUI ruling SC-I).
            // Move the pin deliberately: a newer `revision:`, then `swift package update`.
            .package(url: "https://github.com/mburger89/MetalUI",
                     revision: "70ed000c69f57c2cd04f175ba4a795200210ef1c",
                     traits: metalUITraits),
        ],
        targets: [
            chidapi,
            .executableTarget(
                name: "SMKConfigurator",
                dependencies: [
                    .product(name: "MetalUI", package: "MetalUI"),
                    .product(name: "MetalUISDL", package: "MetalUI", condition: portable),
                    // The portable text system is the text system off macOS
                    // (`makeApp()`). Unconditional, not `condition: portable`:
                    // with these two filtered out of this target on macOS while
                    // the test target names them, the default build system
                    // drops their C modules' map files from the test target's
                    // compile (`unable to resolve module dependency:
                    // 'CFreeType'`, gap MG-26). macOS links them unused.
                    .product(name: "MetalUIPortableText", package: "MetalUI"),
                    .product(name: "MetalUISystemFonts", package: "MetalUI"),
                    "CHidapi",
                ],
                exclude: allPlatformIconPaths.filter { $0 != iconTree },
                resources: [.copy(iconTree)],
                linkerSettings: hidapiLinkerSettings + [
                    // Windows gives the main thread 1 MB (macOS and Linux 8 MB),
                    // and the window builds and lays out `rootView` there; the
                    // debug build once overflowed 8 MB (gap MG-15). Allowed:
                    // this is a root package nothing depends on (plan §2.1).
                    .unsafeFlags(["-Xlinker", "/STACK:8388608"], .when(platforms: [.windows])),
                ]
            ),
            .testTarget(
                name: "SMKConfiguratorTests",
                dependencies: [
                    "SMKConfigurator",
                    .product(name: "MetalUI", package: "MetalUI"),
                    // A `TextSystem` a test can construct, so `renderFrame` can
                    // build a frame with no window (ShellRenderTests), and the
                    // SDL window test's text system off macOS.
                    .product(name: "MetalUIPortableText", package: "MetalUI"),
                    .product(name: "MetalUISystemFonts", package: "MetalUI"),
                    .product(name: "MetalUISDL", package: "MetalUI", condition: portable),
                ]
            ),
        ]
    )
}
