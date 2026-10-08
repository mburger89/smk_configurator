# The SMK configurator on Linux and Windows (MetalUI's SDL backend) — plan

Date: 2026-10-08. Branch `feat/metalui-cross-platform`, from `origin/main`
`d67f1cd` (the merged macOS port, PR #9). Tasks.md item **C4b**; the user's
decision of 2026-10-03, "macOS first, Linux/Windows after", is why this is a
second item.

MetalUI moves from `e54c3f65086b446d42b09bf6f2fdbf802f7ed52a` to
**`70ed000c69f57c2cd04f175ba4a795200210ef1c`** (its `master`: the `SDL` and
`AccessKit` traits, the portable image decoder, the field chrome, the
toolbar). Gaps found on the way go on
[`2026-10-06-metalui-gaps.md`](2026-10-06-metalui-gaps.md), continuing the
`MG-` numbers. The macOS port's plan,
[`2026-10-06-metalui-port-plan.md`](2026-10-06-metalui-port-plan.md), stays
the reference for everything this plan does not change. Its §4.1 ruling (one
source tree, one target named `SMKConfigurator`) still holds. §2 below
replaces only the per-platform split it made.

MetalUI citations are to its `CLAUDE.md` rule paragraphs and decision ids
(`PX-`, `MN-`, `MD-`, `SV-`, `CR-`, `AI-`) and to source files at `70ed000`.

**What binds every lane:**
- macOS keeps building, and every test stays green, after every lane. That
  includes `BinaryFormatAgreementTests` and every model test.
- Nothing in MetalUI is edited. A gap is appended to the gaps list and the
  app uses the workaround.
- Bluetooth stays macOS-only (CoreBluetooth). HID through hidapi works on all
  three platforms.
- Each platform bundles only its own icon tree. The SF Symbols licence (see
  `THIRD-PARTY-NOTICES.md`) forbids the macOS PNGs anywhere else.
- No `git push`. CI first runs when the user pushes.

**Baseline** (macOS, `d67f1cd`, Swift 6.4, `swift build` then `swift test` in
this worktree): `Test run with 256 tests in 32 suites passed`, 0 `error:` (§7). Lane 1 takes it again after the dependency bump.

---

## 1. Every macOS-only construct, and its Linux/Windows answer

What the survey found: every `#if`, `import`, AppKit/CoreBluetooth use,
bundle or resource lookup, file path and `UserDefaults` use in `Sources/` and
`Tests/`, plus every MetalUI call whose behaviour differs on SDL. "SDL" below
means MetalUI's `SDLPlatform` on Linux and Windows.

### 1.1 App and window

| # | Construct (where) | macOS today | Linux / Windows answer |
|---|---|---|---|
| A1 | `let app = try App()` (`main.swift`) | AppKit + Metal, CoreText | `App(platform: try SDLPlatform(), textSystem: { PortableTextSystem(resolver: resolver) })` with `resolver = try SystemFonts.resolver()`, behind `#if canImport(MetalUISDL)`. This is the shape `metalui new --cross-platform` generates (`Scaffold.swift` `mainSource`). `App()` exists only under `#if canImport(MetalUIAppKit)` (`App.swift:47`), so it cannot be named off macOS. |
| A2 | `app.run()` from top-level code (`main.swift`) | runs the AppKit loop; the main queue drains (`SV-H`) | unchanged. SDL's loop drains the main queue once per iteration (`SV-H` item 1), so the device monitor's `Task`, the file dialogs' continuations and `sendToDevice` all run. |
| A3 | `.font(.system(…, design: .monospaced))` at 8 sites (hex fields, step rows, the inspector's byte counts) | SF Mono through CoreText | **gap MG-25.** `SystemFonts.resolver()` registers no family for any `FontDesign`, so `.monospaced` draws the default sans face. Workaround in `makeApp()`: `resolver.register(design: .monospaced, family: "DejaVu Sans Mono")` on Linux and `"Consolas"` on Windows. A family that is not installed falls back to the default face (`PortableFontResolver.register(design:family:)`), so this is safe. |
| A4 | Text metrics | CoreText | `PortableTextSystem`: FreeType + HarfBuzz over the platform's fonts. The default family is Segoe UI on Windows; on Linux it is fontconfig's `sans-serif`, then DejaVu Sans, Noto Sans, … (`SystemFonts.swift:60-70`). Widths differ from SF: DejaVu Sans is wider. Fixed-width columns (the inspector, chips, the rail) may clip or wrap differently. Parity check P4 (§5). The CI image needs a font package: `fonts-dejavu-core` (with no faces, `resolver()` throws `NoFontsFound`). |
| A5 | `openWindow(size: WindowMetrics.idealSize, minSize: WindowMetrics.minSize)` | 1440-wide minimum; computed height; the OS clamps the launch size to the screen | `setContentSizeLimits` → `SDL_SetWindowMinimumSize` (`SV-M`). **Two app-visible differences.** (1) The drawn toolbar strip (§1.2, M1) takes 39 points off the root's height and does not grow the window (divergence 136, `MD-K`). `WindowMetrics` adds `toolbarStripHeight` (39 off macOS, 0 on macOS) to `chromeHeight`, so KEY mode keeps its floor. The floor goes from 597 to 636; the "under 730" laptop bound still holds. (2) **A 1440-point floor is wider than many Windows/Linux screens in logical points.** A 1920×1080 panel at 150 % scaling is 1280 points wide, and a 1366×768 panel at 100 % is 1366. SDL then opens a window larger than the screen, and the right-hand columns and the status bar's right end cannot be reached. This plan keeps 1440 (the user's decision, port plan §1.1). **It is an open question for the user, not settled here** (§6, Q1). |
| A6 | `app.commands { … }` (`AppCommands.swift`): File (New ⌘N, Open… ⌘O, Save ⌘S, Save As… ⇧⌘S, Import…, Export…) and View (Advanced Mode, Appearance ▸ Light/Dark/System) | `NSMenu` main menu, plus the standard AppKit items (Quit, Close, Edit, Window) | **gap MG-23.** `SDLPlatform.setMenuBar` records the bar and draws nothing (`MN-I` item 3, `SDLPlatform.swift:146-155`): no menu bar, and no in-window menu bar (deferred in MetalUI, no owner). Shortcuts still fire through the window's command stage (`MN-J`). Import…, Export…, Advanced Mode and Appearance have **no shortcut**, so without a workaround they would be unreachable. Workaround: M1. |
| A7 | `.keyboardShortcut("n")` etc. (`AppCommands.swift`), default modifier `.command` | ⌘N | **gap MG-24.** On SDL, `.command` is the GUI key (Super / the Windows key: `SDLBridge.c:800`, `SDL_KMOD_GUI → MUI_MOD_COMMAND`). Modifiers match exactly (`IX-F` item 2), so ⌘N would mean Win+N. Windows takes Win+N (notifications), Win+O and Win+S (search) itself, and GNOME takes Super. Workaround: one app constant, `primaryShortcutModifier` (`.command` on macOS, `.control` elsewhere), on every app shortcut; Save As becomes `[primary, .shift]`. Text-field editing keys already follow the platform (Ctrl+C/V/X/A/Z off Apple: `TextEditing.platform`, `TI-D`), so only the app's own shortcuts change. |
| A8 | The standard AppKit items (Quit ⌘Q, Close ⌘W, Hide, Minimize) | given free by `App.commands` (`MN-I` item 2) | Not drawn on SDL. Closing the window quits (the window manager's close button, Alt+F4). Neither the app nor MetalUI binds Ctrl+Q or Ctrl+W. Listed as parity item P2; not a gap, since Linux and Windows apps vary here. |
| A9 | `.preferredColorScheme(editor.appearanceMode.colorScheme)` (`ContentView`) | content and window decoration follow | Content follows. SDL decorations follow the **system** theme (`CR-M`, `SDLPlatform.swift:297-300`, documented). Parity item P6. |
| A10 | App icon | none: the port sets no `App.icon` and ships no `.icns`, so the generic executable icon shows (`swift run`) | Unchanged: no app icon on any platform. The packaging recipe (§3) leaves room for one. Making an app icon is outside this item. |

### 1.2 What the app draws differently on SDL

| # | Construct | macOS | Linux / Windows |
|---|---|---|---|
| M1 | The File and View menus (A6) | the menu bar | **A `.toolbar` on Linux/Windows only**, drawn by MetalUI as a 39-point strip across the top (`setToolbar` answers `false` on SDL, divergence 136, `MD-K`). The strip holds New, Open, Save, Save As, Import and Export as `Button`s with `Image` labels (the six toolbar PNGs already bundled per platform and undrawn since the port: `AppIcon.newDoc…exportFile`, gap MG-3), an "Advanced" `Toggle`, and an "Appearance" `Picker(.menu)`. All three are in the closed item set (divergence 135). Each item calls the same action as its menu item: one shared table of file commands feeds both the menu and the toolbar, so the two cannot drift. Outcomes arrive as `InputEvent.toolbarAction` under `StateDispatch`. On macOS the toolbar is **compiled out** (`#if !os(macOS)`): a macOS toolbar would bring back the icons the user deleted with the fake titlebar (port plan §2.2 W8), and that is the user's call. `ToolbarScope` is not an `Element` (`MD-S`), so it goes inside the root's first container (`ContentView`'s `Column`), not on `rootView`. |
| M2 | Context menus and `.pickerStyle(.menu)` (the macro library's collection picker; the inspector's key and layer pickers) | native `NSMenu` | drawn by the window: `presentMenu` answers `false` (`MN-C` item 3, `MN-F`); a long picker is the scrolling drawn menu (`SV-AK` items 3–6). No app change. The KEY chooser over several hundred keys (gap MG-8) is the longest one, so it is parity item P5. |
| M3 | `.alert` (load error in `ContentView`; KEY layer delete; macro library delete) | `NSAlert` sheet | drawn and held modal by the window (`AlertPanel.swift`, `SV-AK` item 1): Return is the default button, Escape the cancel. No app change. |
| M4 | File dialogs: `window.fileDialogs` / `@Environment(\.fileDialogs)` `openFiles(allowedContentTypes: [.json])`, `saveFile(contentTypes: [.json], defaultFilename:)` (keymap, theme, design, macro import/export) | `NSOpenPanel`/`NSSavePanel` | `SDL_ShowOpenFileDialog`/`SDL_ShowSaveFileDialog` (`SV-G`), filtered by extension only (`*.json`, `SV-E`). No title, as on macOS today (gap MG-5). On Linux, SDL needs `xdg-desktop-portal` or `zenity` at run time. Without either the dialog **fails**, and the app's existing `catch` reports it through `editor.loadError` → the alert (`KeymapFileActions.chooseFile`). Parity item P3. |
| M5 | `.help` tooltips (about 15 sites) | drawn, tick-timed tooltip (MetalUI draws them everywhere) | the same. |
| M6 | Drag and drop: palette chip → key cap (`PaletteDrawerView`/`KeyCapView`), ADD STEP row → "Add a step" card (`MacroEditorViews`/`ContentView`) | MetalUI's own in-window drag (`DN-`) | the same. Only a drag that **leaves** the window goes to the platform (`beginExternalDrag`, `false` on SDL), and the app has none. |
| M7 | `onAppear`/`onDisappear` (the DEV pane starts and stops the device monitor), `onChange` (load error) | lifecycle drain | the same: portable. |
| M8 | Accessibility | NSAccessibility | AccessKit, with the `AccessKit` trait on (`PX-H`). Unverified on screen; parity item P9 (an agent cannot run a screen reader, `IX-AE`). |

### 1.3 Model and device layer

| # | Construct (where) | macOS | Linux / Windows |
|---|---|---|---|
| D1 | `BLECentral`, `BLETransport`, `BLEUploadUUIDs` (`Device/`), `#if canImport(CoreBluetooth)` | BLE upload to ESP32-C6 | **Stays macOS-only.** It already compiles out: the DEV pane shows only the USB transport card, there is no "Test Connection" button, and the inspector has no BLE/Peripheral/Signal/Max-write lines. `sendToDevice` throws `noDeviceFound` when USB is absent. `BLEConnectionStateTests` and `BLEUploadUUIDsTests` compile out. Parity item P7 states it. |
| D2 | `USBRawHIDTransport` (hidapi; vendor usage page 0xFF00, usage 0x01) | Homebrew `hidapi` | **Linux:** `libhidapi-dev` (hidraw backend; the manifest links `hidapi-hidraw`). Ubuntu 24.04's hidapi 0.14 reports usage pages from the report descriptor. **A user without a udev rule cannot open `/dev/hidraw*`**: `try? USBRawHIDTransport()` is `nil`, so the DEV pane reads "Not connected" even with the board plugged in. README gains the udev rule (lane 3). Parity item P8. **Windows:** vcpkg `hidapi` (`hidapi.lib`, the existing manifest line). `hidapi.dll` goes beside the executable (§3). |
| D3 | `defaultKeymapURL = homeDirectoryForCurrentUser/esp/SMK/keymap.json` (`EditorState.swift:7`) | loaded at launch if present | Linux: `~/esp/SMK/keymap.json`; Windows: `%USERPROFILE%\esp\SMK\keymap.json`. A missing file is skipped silently (`try? Data(contentsOf:)`), so there is no change. |
| D4 | `applicationSupportDirectory/SMKConfigurator/{Designs,Themes}` (`EditorState.swift:10`) | `~/Library/Application Support/…` | swift-corelibs-foundation: Linux `$XDG_DATA_HOME` or `~/.local/share/SMKConfigurator/…`; Windows `%LOCALAPPDATA%\SMKConfigurator\…` (expected; **lane 3 records the actual path** on each platform from a run). `JSONFileStore` creates the directory. |
| D5 | `UserDefaults.standard` (drawer height, Advanced, appearance, macro capacity) | the app's domain | corelibs `UserDefaults`, persisted under the user's home on Linux; on Windows it is not documented. The suite-based tests (`JSONFileStoreTests`, `MacroCapacityTests`) already run on Linux CI. Lane 3 runs them on Windows for the first time (the old workflow only compiled them) and records whether a value survives a relaunch there (parity item P10). |
| D6 | `IconLoader`: `Bundle.module.url(forResource:withExtension:subdirectory: "Icons/<scheme>")`, then `ImageBitmap(contentsOfFile:)` | resource bundle in the build directory or the `.app` | `Bundle.module` is generated for every platform. The bundle is `SMKConfigurator_SMKConfigurator.resources` beside the executable on Linux and Windows. **At `70ed000` PNGs decode through MetalUI's vendored stb_image on every platform, macOS included** (`PX-` "One decoder everywhere", divergence 138). `IconLoaderTests` therefore runs everywhere: it was excluded off macOS only because MetalUI was not declared there. |
| D7 | `BinaryFormatAgreementTests` reads `~/esp/SMK` (`NSHomeDirectory()`) | runs when the firmware repo is checked out, skips otherwise | skips in CI and on the VM (no firmware checkout). It stays green: a skip is not a failure. It runs on the developer's Mac. |
| D8 | Generated files `KeyCodesGenerated.swift`, `BLEUploadUUIDs.swift` | byte-identical to the firmware repo's | unchanged. They are the reason for §2's single-target shape. |

### 1.4 What the dependency bump changes on macOS (`e54c3f6` → `70ed000`)

From MetalUI's merges #49 (`feat/proposal-controls`), #50
(`feat/port-gaps-medium`) and #51 (`feat/portable-app`):

1. **`TextField` and `TextEditor` draw SwiftUI's bordered field by default**
   (`MD-B`, `MD-C`). The app's `fieldChrome()` helper (gap MG-20,
   `Views/UIStyle.swift`) adds its own padding, fill and 1-point border, so
   without a change every field would have **two** borders. Lane 1 resolves
   this one way or the other: either drop the helper's border and fill and
   keep MetalUI's chrome, or keep the helper and write
   `.textFieldStyle(.plain)` on each field. The lane records which, with a
   launch look if the screen is unlocked. A changed look on macOS counts as a
   change: report it.
2. PNGs now decode through stb_image instead of ImageIO (divergence 138).
   The icons are untagged 8-bit RGBA, so no visible change is expected.
3. Fixed upstream, not adopted here: MG-2 (`@Environment(Type.self)`,
   `MD-H`), MG-3 (`.toolbar`, `MD-I`/`MD-J`), MG-14 (a legacy container
   honours `layoutPriority`, `MD-G`), MG-20 (field chrome, `MD-B`), plus
   `.task` (`PX-F`). Adopting them is follow-up work, not this item, with one
   exception: lane 2 uses `.toolbar` for M1. Lane 1 adds a "Status at
   `70ed000`" line to each of these entries in the gaps list. It does not
   delete or renumber them.
4. Anything else lane 1's `swift build` or `swift test` shows after the bump
   (a new warning, a deprecation, a changed count) is written into §7.

---

## 2. Manifest shape, and how Model/ and Device/ stay UI-free

### 2.1 Ruling: one executable target `SMKConfigurator` on every platform; the old library shape is kept behind `SMK_UI_FREE=1`

The port plan's §4.1 reason still holds. The generated files carry no access
modifiers, so a separate `SMKCore` module is ruled out. One target named
`SMKConfigurator` stays over `Sources/SMKConfigurator/`. What changes:

- **Default (every platform):** an `executableTarget` with `Model/`,
  `Device/`, `Views/` and `main.swift`, depending on
  `.product(name: "MetalUI")`, `CHidapi` and, with
  `condition: .when(platforms: [.linux, .windows])`, `MetalUISDL`,
  `MetalUIPortableText` and `MetalUISystemFonts`. The MetalUI dependency
  takes `traits: metalUITraits`: `["SDL", "AccessKit"]` under
  `#if os(Linux) || os(Windows)`, `[.defaults]` on macOS. These are
  getting-started's lines, and the scaffold's (`Scaffold.swift:243-254`).
  Resources: `.copy(iconTree)`, where `iconTree` is the host platform's
  `Resources/<Platform>/Icons`, chosen by `#if os(...)`. The other two trees
  are excluded, so the SF Symbols PNGs never reach a Linux or Windows build.
  The test target `SMKConfiguratorTests` takes **every** test file on every
  platform. `IconLoaderTests`, `ShellRenderTests`, `PaneRenderTests`,
  `PaneLogicTests` and `MacroPaneTests` now compile on Linux and Windows. The
  one AppKit-only test, `ShellRenderTests.everyModeDraws`, which calls
  `App()`, is gated `#if os(macOS)`. Its Linux/Windows twin is an
  `SDLPlatform` window test (§4.3).
- **`SMK_UI_FREE=1` (any platform):** the manifest reads
  `Context.environment["SMK_UI_FREE"]` and declares today's Linux/Windows
  shape instead. That is a library `.target` over `Model/` and `Device/` only
  (`exclude: ["Views", "main.swift", "Resources"]`), depending on `CHidapi`
  alone. MetalUI is **not declared**. The test target keeps today's exclude
  list (the five files above). This is the old enforcement, kept as it was:
  a `Model/` or `Device/` file that imports MetalUI or names a view type
  fails `SMK_UI_FREE=1 swift build --build-tests`.
- **`swift-tools-version` stays 6.2.** Dependency traits need 6.1. The
  toolchain must be 6.4 or later anyway, because it has to parse MetalUI's
  6.4 manifest. Platforms stay `.macOS(.v26)`.
- **Windows main-thread stack: `/STACK:8388608`** through
  `linkerSettings: [.unsafeFlags(["-Xlinker", "/STACK:8388608"], .when(platforms: [.windows]))]`.
  Reasons: Windows gives the main thread 1 MB, where macOS and Linux give
  8 MB (MetalUI's "Windows threads have 1 MB stacks" hazard). The window
  builds **and lays out** `rootView` on the main thread. The debug build
  already overflowed **8 MB** before pane-boundary type erasure (gap MG-15).
  MetalUI's own 1 MB guard (`DemoStackBudgetTests`) can only run the
  *build* off the main thread, because layout's `assumeIsolated` traps
  there, so it could not prove the app safe. `unsafeFlags` is allowed
  because this package is a root package that nothing depends on. Lane 3
  verifies the flag on the VM: `llvm-readobj --file-headers` (or
  `dumpbin /headers`) reads `SizeOfStackReserve: 8388608`.
- `CHidapi` and `hidapiLinkerSettings` are unchanged.

**Why an environment switch and not a CI-only `swiftc -typecheck` script.**
The switch reuses the exact shape CI has enforced since the port, with its
test list. It needs no hand-maintained compiler command line: the `CHidapi`
module map, hidapi's include path per platform, the Observation module. It
reproduces locally with one variable. **Lane 1 must measure** that SwiftPM
re-evaluates the manifest when only the variable changes (manifest caching).
The mutation: add `import MetalUI` to one `Model/` file. Then
`SMK_UI_FREE=1 swift build --build-tests` must fail with `no such module
'MetalUI'`, and a plain `swift build` right after it, same scratch path,
must succeed. Lane 1 reverts the mutation and records both results. If the
cache defeats the switch, the fallback is a separate
`--scratch-path .build-ui-free` for the UI-free build, recorded the same
way. If that also fails, fall back to a `Scripts/check-ui-free.sh` that
type-checks `Model/` and `Device/` alone with `swiftc -typecheck`.

### 2.2 Sketch (lane 1 writes the real one)

```swift
// swift-tools-version: 6.2
import PackageDescription

/// `SMK_UI_FREE=1 swift build --build-tests`: Model/ and Device/ alone, no UI
/// dependency declared -- what proves the model has no UI type (plan §2.1).
let uiFree = Context.environment["SMK_UI_FREE"] == "1"

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
// … chidapi, hidapiLinkerSettings unchanged …
// uiFree ? today's #else Package (library + excludes) : the executable Package
```

---

## 3. Resources, icons and shaders per platform

| | macOS | Linux | Windows |
|---|---|---|---|
| App icons (rail, toolbar) | `Resources/macOS/Icons` (SF Symbols renders) | `Resources/Linux/Icons` (Adwaita, LGPL/CC-BY-SA) | `Resources/Windows/Icons` (Fluent, MIT) |
| In the build | `SMKConfigurator_SMKConfigurator.bundle` (SwiftPM) | `SMKConfigurator_SMKConfigurator.resources/Icons/{light,dark}/*.png` beside the executable | the same, beside `SMKConfigurator.exe` |
| MetalUI's renderer | `MetalUI_MetalUIRender.bundle` (Metal shaders; `AI-N`) | SDL GPU shaders: `MetalUISDLShaders/` **beside the executable** first, then the build machine's `.build/checkouts/MetalUI/Backends/SDL/Shaders/compiled` via `#filePath` (`PX-P`). `swift run` on the build machine therefore needs nothing; a moved app needs the copy. | the same |
| Native libraries | Homebrew `hidapi` (dynamic) | `libSDL3.so` (3.4 or later; see below), `libhidapi-hidraw.so`. AccessKit is static. | `SDL3.dll`, `hidapi.dll` beside the executable. AccessKit is static (`docs/packaging.md` §Windows 3). |
| Install integration | `Scripts/run.sh` (swift-bundler, `Bundler.toml`) | a `.desktop` entry plus the hicolor theme (`docs/packaging.md` §Linux). There is no app icon (A10), so the entry names none. | an `.ico` embedded through `rc` (`docs/packaging.md` §Windows 2). No app icon (A10). |

The per-platform icon trees in the repo already have identical file names
(11 icons × 2 schemes, the same 66 px rail and 48 px toolbar sizes). Their
content differs, as it should.

**SDL on a Linux user's machine.** MetalUI's CI image builds SDL 3.4.16 with
X11 and Wayland **off** (offscreen and console only). That is fine for
building and testing, but such a library opens no window on a desktop. A
user needs a distribution `libsdl3` 3.4 or later, or SDL built with its
defaults. README says so (lane 3). This plan produces no release artifact.

**Packaging scripts (lane 3):** `Scripts/package-linux.sh` and
`Scripts/package-windows.ps1`. Each builds `-c release`, then lays out
`dist/`: the executable, the `.resources` bundle, `MetalUISDLShaders` copied
from `.build/checkouts/MetalUI/Backends/SDL/Shaders/compiled`, and on
Windows `SDL3.dll` and `hidapi.dll`. Verified means: the moved `dist/` app
starts. On Linux that is a 5-second launch in the image, from a directory
other than the build tree (§4.3). On Windows it is the VM.

---

## 4. CI on Swift 6.4 with SDL3 and AccessKit

### 4.1 Linux (`.github/workflows/linux-build.yml`)

**Ruling: build inside MetalUI's own CI image, plus one derived layer.**
`Backends/SDL/linux/Dockerfile` already gives `swift:6.4-noble`, SDL 3.4.16
from source on `/usr`, Mesa lavapipe, and AccessKit on `/usr` (x86_64
prebuilt; cargo build on aarch64), with `SDL_VIDEO_DRIVER=offscreen`. A
consumer then needs no flags (`PX-I` item 5). Steps:

1. `actions/checkout`. Read MetalUI's pinned revision from `Package.resolved`
   (`jq`), then `git clone --filter=blob:none https://github.com/mburger89/MetalUI`
   and `git checkout <rev>` into `$RUNNER_TEMP/MetalUI`.
2. `docker/build-push-action`: context `$RUNNER_TEMP/MetalUI/Backends/SDL`,
   file `linux/Dockerfile`, tag `metalui-portable`, GHA cache scope
   `metalui-portable-<rev>`.
3. Build `Scripts/ci/Dockerfile.linux`: `FROM metalui-portable`, then
   `apt-get install libhidapi-dev fonts-dejavu-core`, tag `smk-linux`. The
   same two files are used locally (§4.3), so CI and the local check cannot
   differ.
4. `docker run -v $PWD:/work -w /work smk-linux bash -ec '…'`:
   - `swift build` (the app with SDL and AccessKit)
   - `swift test` (the summary line is printed)
   - `SMK_UI_FREE=1 swift build --build-tests --scratch-path /tmp/ui-free`
     and `SMK_UI_FREE=1 swift test --scratch-path /tmp/ui-free` (the UI-free
     proof, §2.1)
   - the launch smoke: `timeout 5 .build/debug/SMKConfigurator`, which must
     exit **124**, meaning it was still running when killed. This proves
     startup only: the offscreen driver presents no frame.

The old `SwiftyLab/setup-swift` 6.2 step goes. The image carries Swift 6.4.

### 4.2 Windows (`.github/workflows/windows-build.yml`)

MetalUI's `sdl-gpu-linux.yml` Windows job shows the way:

- `compnerd/gha-setup-swift@v0.5.0` with `swift-version: swift-6.4.0-release`
  and `swift-build: 6.4.0-RELEASE`. This replaces 6.2.
- **SDL3:** download `SDL3-devel-3.4.16-VC.zip` and expand it. Export
  `SDL3_INCLUDE` and `SDL3_LIB` (`lib\x64`), and add `lib\x64` to
  `GITHUB_PATH` (for `SDL3.dll`).
- **hidapi:** vcpkg as today (cached `vcpkg_installed`). `INCLUDE`/`LIB` stay
  as today. Add `vcpkg_installed\<triplet>\bin` to `PATH` (for `hidapi.dll`).
- **AccessKit:** run `swift package resolve`, then
  `python .build\checkouts\MetalUI\Backends\SDL\scripts\fetch-accesskit.py --print-flags > accesskit-flags.txt`.
  That writes one SwiftPM flag per line (`PX-I` item 2).
- **Build:** `swift build @flags`, where the flags are
  `-Xcc -I$SDL3_INCLUDE -Xswiftc -L$SDL3_LIB` plus the AccessKit lines. Keep
  the long-paths step and the three-attempt retry: the crash it works around
  was the compiler's, not SwiftCrossUI's.
- **Tests:** `swift build --build-tests @flags`, then `swift test @flags`
  (run, not only compiled). Lane 3 decides whether CI runs them, based on
  what the VM shows. **Known risk:** testing an **executable** target on
  Windows (`@testable import` of a target with `main.swift`). If the VM
  shows it cannot link, CI runs the UI-free shape's tests on Windows
  (`SMK_UI_FREE=1 swift test`) and compiles the app's tests, and the plan
  records why.
- **UI-free proof** on Windows too: `SMK_UI_FREE=1 swift build --build-tests`
  with a separate `--scratch-path`.

The tests open no SDL window, so a GPU-less runner is fine.

### 4.3 Local verification

- **Linux:** OrbStack (`orb start` if it is down). Build MetalUI's image
  from `/Users/maxburger/Developer/MetalUI`:
  `docker build -t metalui-portable -f Backends/SDL/linux/Dockerfile Backends/SDL`
  (read-only use of that checkout; the tag already exists, and rebuilding is
  cheap from cache). Then build `Scripts/ci/Dockerfile.linux` as
  `smk-linux`. Run with this worktree mounted at `/work` and the volume
  **`smk-xp-build`** as the scratch path (`--scratch-path /build/…`), so the
  macOS `.build` is never touched. The local machine is Apple silicon, so
  the container is **aarch64** (CI is x86_64); record that. No `pkill`, no
  `docker system prune`, no other volume. Never stop OrbStack.
- **SDL window test (Linux image only):** a test gated
  `#if !os(macOS)` and on `SMK_RUN_SDL_WINDOW_TEST=1`. It opens an
  `SDLPlatform` window with `startsDisplayLink: false` and walks every rail
  mode and both schemes with `drawFrameIfNeeded()`, as `everyModeDraws` does
  on AppKit. This covers the app's themes, the drawn toolbar strip and the
  lifecycle drain on SDL. It is never compiled into a macOS process: SDL
  video in a macOS test process can `exit(0)` mid-run (MetalUI CI hazards).
  On Windows it would need the interactive session, so it is not run over
  SSH.
- **Windows:** the UTM VM (`ssh metalui-win`, PowerShell). It was
  **stopped** at planning time. Start it with
  `/Applications/UTM.app/Contents/MacOS/utmctl start Windows`. Stop it
  afterwards only if this lane started it and no other workflow is using it.
  Clone with `git clone -c core.symlinks=true`: MetalUI's shader header is a
  symlink inside the checkout SwiftPM makes, and SwiftPM's own clone follows
  the global git config, so lane 3 also sets
  `git config --global core.symlinks true` on the VM and records it. The VM
  is ARM64, so it uses SDL's `lib\arm64`, AccessKit's ARM64 prebuilt and
  vcpkg's `arm64-windows` hidapi (or hidapi built with CMake if the VM has
  no vcpkg). The x64 emulation route (`--build-system native --triple
  x86_64-unknown-windows-msvc`) is optional. At minimum: a build and
  `swift test`. A GUI launch goes through the interactive scheduled task
  (MetalUI `CLAUDE.md`, Windows paragraph). If it runs, a screenshot taken
  in that session (`System.Drawing` `CopyFromScreen`, copied back with
  `scp`) is the only look at the app on Windows an agent can get, and it is
  optional.

---

## 5. Parity checklist (Linux/Windows against macOS), for the final check

Each line says what the user sees. "Verified" needs the run that showed it.
A look nobody could take is written as **not checked**, never as passing.

| # | Area | macOS | Linux / Windows (expected) | How it is checked |
|---|---|---|---|---|
| P1 | File actions | File menu, ⌘N/⌘O/⌘S/⇧⌘S | the toolbar strip's six buttons; Ctrl+N/O/S, Ctrl+Shift+S | a unit test on the shared command table and the modifier; the SDL window test draws the strip; pressing keys is a human check |
| P2 | View options | View menu: Advanced Mode, Appearance | the strip's "Advanced" toggle and "Appearance" menu picker; no menu bar; no Quit/Close shortcut (close the window) | SDL window test (builds); human |
| P3 | Open / Save dialogs | `NSOpenPanel`/`NSSavePanel` | SDL's native dialog (GTK portal or zenity on Linux, the common dialog on Windows), `*.json` filter, no title; on Linux with neither portal nor zenity, an error alert | human (VM interactive session for Windows) |
| P4 | Text | SF Pro / SF Mono | Segoe UI / Consolas (Windows); DejaVu Sans / DejaVu Sans Mono (Linux); clipping in fixed-width columns possible | headless render tests run on Linux and Windows (no trap); the look is human or the VM screenshot |
| P5 | Menus and pickers | `NSMenu` | drawn menus; the key chooser scrolls | human |
| P6 | Dark mode | content and title bar follow View ▸ Appearance | content follows; the title bar follows the system | SDL window test (both schemes build); human |
| P7 | Bluetooth | BLE card, Test Connection, BLE details | **absent**: USB only; "Send to Device" without USB reports no device | compiled out; read in the source |
| P8 | USB | hidapi | hidapi; Linux needs the udev rule (README) | build and link only; a real board is a human check |
| P9 | Screen reader | VoiceOver | AccessKit (Orca, Narrator) | not checked (an agent cannot) |
| P10 | Persistence | `~/Library/Application Support`, `UserDefaults` | XDG data dir / `%LOCALAPPDATA%`; corelibs `UserDefaults` | suite tests on Linux and Windows; the real path recorded by lane 3 |
| P11 | Window | 1440 × computed height, OS-clamped | the same floor plus 39 for the strip; may exceed a small logical screen (Q1) | `WindowMetrics` test per platform |
| P12 | Icons | SF Symbols renders | Adwaita (Linux), Fluent (Windows), light/dark by scheme | `IconLoaderTests` on every platform |
| P13 | Tooltips, alerts, drag and drop | MetalUI-drawn tooltips, `NSAlert`, in-window drags | tooltips and drags the same; alerts drawn in-window | portable code; human |

---

## 6. Lanes (sequential; each leaves macOS green)

The lanes run one at a time. Lane N+1 starts from lane N's commit. File
ownership is disjoint, with one exception: the gaps list is appended to by
any lane that finds a gap, and this plan's §7 records every lane's results.

### Lane 1 — dependency, manifest, platform app creation, Linux build

**Files:** `Package.swift`, `Package.resolved`, `Sources/SMKConfigurator/main.swift`,
`Views/UIStyle.swift` (the field-chrome fallout, §1.4 item 1; plus each
field's call site if `.textFieldStyle(.plain)` is chosen), `Views/WindowMetrics.swift`
(`toolbarStripHeight`), `Tests/SMKConfiguratorTests/ShellRenderTests.swift`,
and the new `Tests/SMKConfiguratorTests/SDLWindowTests.swift`.

1. Bump the pin to `70ed000…` and run `swift package update`. Take macOS
   build and test (summary lines into §7), and fix the field double border.
2. Write the manifest of §2.2: traits, conditional SDL products, a
   per-platform `iconTree`, every test file in the test target, the
   `SMK_UI_FREE` shape, the Windows `/STACK` flag.
3. `main.swift`: `makeApp()` as in A1, registering the monospaced family on
   Linux and Windows (A3). Window sizes come from `WindowMetrics`.
   `WindowMetrics.toolbarStripHeight` is 39 off macOS and 0 on macOS (the
   value from MetalUI divergence 136; MetalUI's constant is internal). The
   `windowMetrics` test reads it.
4. Gate `everyModeDraws` with `#if os(macOS)`. Add the SDL window test
   (§4.3), env-gated, compiled only off macOS.
5. Add "Status at `70ed000`" lines to MG-2, MG-3, MG-14 and MG-20 (§1.4 item 3).

**Closes when:**
- macOS: `swift build` prints 0 `error:`, and `swift test` prints at least
  the baseline count, all passing.
- In the Linux image (aarch64, `smk-xp-build` volume): `swift build` of the
  app; `swift test` with every suite passing (CI and Linux skip
  `BinaryFormatAgreementTests`); `SMK_RUN_SDL_WINDOW_TEST=1 swift test
  --filter SDLWindow` passing; the launch smoke exits 124.
- The UI-free mutation of §2.1, with both results recorded.
- Windows is not touched yet.

### Lane 2 — what the app does differently on SDL: toolbar, shortcuts

**Files:** `Views/AppCommands.swift`, `Views/ContentView.swift`, the new
`Views/PlatformToolbar.swift` (the `#if !os(macOS)` toolbar and the shared
file-command table), and the new `Tests/SMKConfiguratorTests/PlatformChromeTests.swift`.

1. Add `primaryShortcutModifier` (A7) and apply it to every
   `.keyboardShortcut` in `AppCommands`.
2. Add one table of file commands (title, `AppIcon`, shortcut, action), read
   by both `installAppCommands` and the toolbar. The menu's titles and order
   stay as they are on macOS.
3. Add the toolbar (M1), compiled out on macOS, written inside
   `ContentView`'s first container (`MD-S`): six icon buttons, "Advanced",
   "Appearance".
4. Tests: the modifier per platform; the toolbar and menu derive from the one
   table (six entries, same order, the shortcuts carry the primary
   modifier). On Linux, the SDL window test (lane 1's file, unchanged) now
   draws the strip.

**Closes when:**
- macOS: build and test green. Nothing visible changes: the toolbar is
  compiled out, ⌘ shortcuts are unchanged, the menu is unchanged. A launch
  look is optional.
- The Linux image: build, `swift test`, the SDL window test, and the launch
  smoke. The strip appears in the window test's walk without a layout trap.
- Gap entries for anything new.

### Lane 3 — CI, packaging, Windows, README, parity

**Files:** `.github/workflows/linux-build.yml`, `.github/workflows/windows-build.yml`,
the new `Scripts/ci/Dockerfile.linux`, the new `Scripts/package-linux.sh`
and `Scripts/package-windows.ps1`, `README.md`, and §5/§7 of this plan.

1. Write the workflows of §4.1 and §4.2. The Linux job's commands are the
   ones lane 1 ran in the image, unchanged.
2. Windows VM: a build (with SDL3, AccessKit and hidapi for ARM64), then
   `swift test` (record the counts, or the executable-target failure and the
   fallback), then the UI-free build, then the `/STACK` read-back. If
   feasible: a `dist/` launch through the interactive task, and a screenshot.
3. The packaging scripts. On Linux, check a moved `dist/` in the image (a
   launch from `/tmp/dist`, exit 124).
4. README: the platform table (Linux and Windows UI: built, tested and
   launched as recorded), build prerequisites per platform (SDL3 3.4 or
   later, AccessKit via `fetch-accesskit.py`, hidapi, fonts on Linux), the
   Linux udev rule for hidraw, and what is missing on Linux/Windows (BLE,
   the menu bar replaced by the strip).
5. Fill §5's "verified" column from the runs, and list what stays a human
   check.

**Closes when:**
- macOS green.
- Each workflow's commands have run locally: Linux in the image; Windows on
  the VM, as far as the VM allows, with exactly what ran recorded.
- README is updated.
- Parity is filled in.

### Outside every lane (flagged, not done)

- `CLAUDE.md` in this repo still describes SwiftCrossUI, `--build-system
  native` and "Windows/Linux compile-verified only". It is outside this
  item's file list, so the user should decide on a rewrite.
- **Q1:** the 1440-point minimum width on small logical screens (A5).
- Adopting the upstream fixes in §1.4 item 3 (environment object, `.task`,
  `layoutPriority`, a macOS toolbar).
- An application icon on any platform (A10).

---

## 7. Results

*(Lanes fill this in: the exact summary lines, what ran where, and the
mutations.)*

**Planning baseline, macOS** (`d67f1cd`, before any change):
`swift build`: `Build complete!`, 0 `error:`. `swift test`: `Test run with 256 tests in 32 suites passed` (XCTest: `Executed 0 tests`). `~/esp/SMK` is present on this Mac, so `BinaryFormatAgreementTests` ran rather than skipping. This is the count lane 1 must keep (at least 256) after the bump.
