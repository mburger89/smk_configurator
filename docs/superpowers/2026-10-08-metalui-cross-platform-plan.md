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
| In the build | `SMKConfigurator_SMKConfigurator.bundle` (SwiftPM) | `SMKConfigurator_SMKConfigurator.bundle/Icons/{light,dark}/*.png` beside the executable under Swift 6.4's default build system (swiftbuild; measured in lane 3); `.resources` under `--build-system native` | the same, beside `SMKConfigurator.exe` |
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
`dist/`: the executable, the resource bundle (`.bundle`, or `.resources` under
`--build-system native`; the scripts copy whichever exists), `MetalUISDLShaders` copied
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
   differ. **In CI this build names `--builder default`** (branch check):
   step 2's `setup-buildx-action` leaves a docker-container builder current,
   which cannot see the loaded `metalui-portable`, so `FROM metalui-portable`
   would try to pull it from Docker Hub and fail. Locally the docker driver
   is current, which is why lane 3's local run could not see this.
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
  what the VM shows. **Ruled (lane 3): CI runs them.** On the VM the
  executable target's tests linked and ran: `Test run with 258 tests in 32
  suites passed` (§7), so the fallback below was not needed. **Known risk:** testing an **executable** target on
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

| # | Area | macOS | Linux / Windows (expected) | How it is checked | Result (lane 3, 2026-10-08) |
|---|---|---|---|---|---|
| P1 | File actions | File menu, ⌘N/⌘O/⌘S/⇧⌘S | the toolbar strip's six buttons; Ctrl+N/O/S, Ctrl+Shift+S | a unit test on the shared command table and the modifier; the SDL window test draws the strip; pressing keys is a human check | **Verified by test** on all three: `PlatformChromeTests` (7) passed on macOS, in the Linux image and on the Windows VM (strip click at (20, 19) runs New; primary+N runs New; Super+N does not off macOS). A real keyboard: **human check**. |
| P2 | View options | View menu: Advanced Mode, Appearance | the strip's "Advanced" toggle and "Appearance" menu picker; no menu bar; no Quit/Close shortcut (close the window) | SDL window test (builds); human | **Verified by test** (the toolbar actions write Advanced and Appearance, all three platforms). The strip's look: **not checked** (no SDL frame was presented anywhere, below). |
| P3 | Open / Save dialogs | `NSOpenPanel`/`NSSavePanel` | SDL's native dialog (GTK portal or zenity on Linux, the common dialog on Windows), `*.json` filter, no title; on Linux with neither portal nor zenity, an error alert | human (VM interactive session for Windows) | **Not checked**: needs a desktop session. Human check. |
| P4 | Text | SF Pro / SF Mono | Segoe UI / Consolas (Windows); DejaVu Sans / DejaVu Sans Mono (Linux); clipping in fixed-width columns possible | headless render tests run on Linux and Windows (no trap); the look is human or the VM screenshot | **Verified: no trap.** `ShellRenderTests.everyModeRendersHeadlessly`, `PaneRenderTests`, `MacroPaneTests` passed in the Linux image (DejaVu) and on the VM (Segoe UI/Consolas through `SystemFonts`). Clipping/look: **not checked** (no screenshot could be taken). Human check. |
| P5 | Menus and pickers | `NSMenu` | drawn menus; the key chooser scrolls | human | **Not checked.** Human check. |
| P6 | Dark mode | content and title bar follow View ▸ Appearance | content follows; the title bar follows the system | SDL window test (both schemes build); human | Partly: both schemes render headlessly on Linux and Windows (the render tests walk both). Title bar: **human check**. |
| P7 | Bluetooth | BLE card, Test Connection, BLE details | **absent**: USB only; "Send to Device" without USB reports no device | compiled out; read in the source | **Verified by build**: the two `#if canImport(CoreBluetooth)` suites are absent from the Linux and Windows counts (258 in 32 against macOS's 263 in 33, see §7). |
| P8 | USB | hidapi | hidapi; Linux needs the udev rule (README) | build and link only; a real board is a human check | **Verified: builds and links** against hidapi 0.14 (Ubuntu, hidraw) in the image and hidapi 0.15.0 built for ARM64 on the VM; `hidapi.dll` packaged. README carries the udev rule. A real board: **human check**. |
| P9 | Screen reader | VoiceOver | AccessKit (Orca, Narrator) | not checked (an agent cannot) | **Not checked** (an agent cannot run a screen reader). AccessKit links on both. |
| P10 | Persistence | `~/Library/Application Support`, `UserDefaults` | XDG data dir / `%LOCALAPPDATA%`; corelibs `UserDefaults` | suite tests on Linux and Windows; the real path recorded by lane 3 | **Verified.** `JSONFileStoreTests` and `MacroCapacityTests` ran and passed on Linux and, for the first time, on Windows. Measured with a probe program (same corelibs calls): Linux `applicationSupportDirectory` = `~/.local/share` (so `~/.local/share/SMKConfigurator/{Designs,Themes}`), `UserDefaults` file `~/.config/<executable>.plist`; Windows = `C:/Users/<user>/AppData/Local` (so `%LOCALAPPDATA%\SMKConfigurator\…`), `UserDefaults` file `%LOCALAPPDATA%\<executable>.exe.plist`; a value set by one run was read back by the next on both. |
| P11 | Window | 1440 × computed height, OS-clamped | the same floor plus 39 for the strip; may exceed a small logical screen (Q1) | `WindowMetrics` test per platform | **Verified by test** on all three (the `windowMetrics` test reads `toolbarStripHeight`). Q1 stays open for the user. |
| P12 | Icons | SF Symbols renders | Adwaita (Linux), Fluent (Windows), light/dark by scheme | `IconLoaderTests` on every platform | **Verified**: `IconLoaderTests` passed in the Linux image and on the VM, each against its own icon tree; the packaged app found its resource bundle beside the executable (a copy without it stops at `unable to find bundle`). The look: **human check**. |
| P13 | Tooltips, alerts, drag and drop | MetalUI-drawn tooltips, `NSAlert`, in-window drags | tooltips and drags the same; alerts drawn in-window | portable code; human | **Not checked** on screen. Human check. |

**Human checks left** (nobody has seen the Linux or Windows window): P1 keys,
P2 strip look, P3, P4 look, P5, P6 title bar, P8 with a board, P9, P12 look,
P13. The Windows VM lost its logged-in console session when it was restarted
(§7), so the interactive-task route could not run; a person who logs in on
the VM console can run `C:\src\smk-interactive.ps1` through
`C:\src\smk-runtask.ps1`, which launches the packaged app and saves a
screenshot to `C:\src\smk-shot.png`.

### 5.1 Per platform: present, deliberately different, or missing (branch check, 2026-10-08)

The branch checker's tick of P1–P13 per platform, against the macOS app at
`d67f1cd`. "Present" means the same feature is there; "different" means a
deliberate difference whose reason is given; "missing" means the user loses
it. Evidence is §5's last column plus the branch check's own runs (§7).
Nothing below was seen in a window on a screen; on Linux some of it was seen
in pixels SDL GPU drew offscreen (§7, branch check).

| # | Area | Linux | Windows |
|---|---|---|---|
| P1 | File actions | **different**: the toolbar strip's six buttons and Ctrl shortcuts replace the File menu and ⌘ (SDL draws no menu bar, MG-23; `.command` is Super there, MG-24). Test-verified | **different**, same reason. Test-verified on the ARM64 VM |
| P2 | View options | **different**: "Advanced" toggle and "Appearance" menu picker in the strip. **Missing**: Quit/Close/Hide/Minimize items and ⌘Q/⌘W equivalents (close the window; A8, not added on purpose) and the standard Edit menu (field editing keys still work with Ctrl, `TI-D`) | **different** / **missing**, the same |
| P3 | Open / Save | **present** (SDL's portal or zenity dialog, `*.json`), not seen; **missing** when neither portal nor zenity is installed (an error alert instead) | **present** (common dialog), not seen |
| P4 | Text | **different**: DejaVu Sans / DejaVu Sans Mono (MG-25 workaround), wider than SF. Seen in an SDL GPU offscreen render of all five modes, light (§7, branch check): monospaced hex fields correct, no clipping found. On a real desktop: not seen | **different**: Segoe UI / Consolas; renders without a trap; clipping not seen |
| P5 | Menus and pickers | **different**: drawn in the window (`presentMenu` answers `false`); the KEY chooser is the scrolling drawn menu. Not seen | **different**, the same |
| P6 | Dark mode | **present** for the content (both schemes render headlessly); **different**: the title bar follows the system theme (`CR-M`) | **present** / **different**, the same |
| P7 | Bluetooth | **missing** (CoreBluetooth; compiled out, plan D1) | **missing**, the same |
| P8 | USB | **present** (hidapi 0.14 hidraw, links); needs the README's udev rule; no board tried | **present** (hidapi 0.15.0 built for ARM64 on the VM; vcpkg x64 in CI, not yet run); no board tried |
| P9 | Screen reader | **present** (AccessKit linked), unverified | **present** (AccessKit linked), unverified |
| P10 | Persistence | **present**, different path: `~/.local/share/SMKConfigurator`, `UserDefaults` in `~/.config/SMKConfigurator.plist` | **present**, different path: `%LOCALAPPDATA%\SMKConfigurator`, `UserDefaults` in `%LOCALAPPDATA%\SMKConfigurator.exe.plist` |
| P11 | Window | **different**: 39 points taller for the strip (floor 636); the 1440-point minimum width may exceed a small logical screen (Q1, open) | **different**, the same; plus the 8 MB main-thread stack (`/STACK`, read back on the VM) |
| P12 | Icons | **different**: Adwaita set (SF Symbols licence keeps the macOS set off Linux); bundle found beside the moved executable; the rail icons seen in the offscreen render (light) | **different**: Fluent set, the same reason; bundle found beside the moved executable |
| P13 | Tooltips, alerts, drags | tooltips and in-window drags **present**; alerts **different** (drawn in the window, `SV-AK`). Not seen | **present** / **different**, the same |
| — | App icon | none, as on macOS (A10): parity | none, as on macOS: parity |
| — | Release build | **present** (`package-linux.sh` builds `-c release`) | **missing** on ARM64: the toolchain asserts (MG-27); debug package instead. x64 unknown until CI runs |
| — | Seeing the window | startup proven under the offscreen driver only (no frame presented) | startup reached the swapchain over SSH and stopped there (session 0); a console-session launch needs a logged-in user, and none was logged in at either check |

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
- The UI-free shape (§2.1): `SMK_UI_FREE=1 swift build --build-tests` and
  `SMK_UI_FREE=1 swift test`, on macOS and in the Linux image, each on its own
  scratch path. A new test file that imports MetalUI joins the UI-free
  target's `exclude:` list in the same commit.

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
- The UI-free shape (§2.1) builds with its tests and passes, on macOS, in the
  Linux image and on the Windows VM (as for lane 2). The Windows record names
  `PlatformChromeTests` among the suites that ran, or says why the test
  target could not run there.

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

### Lane 1 (2026-10-08)

**The bump** (`e54c3f6` → `70ed000`, `swift package update`, before any
other change), macOS: `swift build` `Build complete! (25.85 sec)`, 0
`error:`, 0 `warning:`; `swift test` `Test run with 256 tests in 32 suites
passed` (XCTest `Executed 0 tests`). No new warning, no deprecation, no count
change. What it changed visibly: §1.4 item 1 (the double field border), below.

**Field chrome (§1.4 item 1). Ruling: MetalUI's chrome on the five
`TextField`s; the app's chrome on the one `TextEditor`.** The helper
`fieldChrome()` is gone from every `TextField` (macro name, library search,
collection, DSN name, THM hex), which now draw MetalUI's default bordered
field: `.surface` fill (the app's theme sets it to the same #FFFFFF / #2C2C2E
as `Chrome.surface`), a 1-point `.separator` border (#E3E3E5 / #3A3A3C,
against the old `Chrome.chipBorder` #E0E0E2 / #48484A), radius 6 (was 5),
insets 6/4 (was 6/3), and now the control focus ring while focused. The text
step's `TextEditor` writes `.textEditorStyle(.plain)` and keeps the old look
through the helper, renamed `editorChrome()`: MetalUI's editor default is a
fill with no border and no text inset (its divergence 133). Gap MG-20 carries
the status line. **Launch look:** the macOS app ran 6 seconds and was killed
(exit 143 from SIGTERM, no crash output); it opened in KEY mode, which holds
no text field, so the new field look itself was **not checked** on screen.

**Manifest (§2).** Written as §2.2, with one change measured on macOS:
`MetalUIPortableText` and `MetalUISystemFonts` are **unconditional**
dependencies of the executable (only `MetalUISDL` is `condition: portable`).
With all three conditional, `swift build --build-tests` on macOS failed in
the test target's dependency scan (`unable to resolve module dependency:
'CFreeType'`, also `CHarfBuzz`, `CSheenBidi`, `CUnibreak`); with the two
unconditional it passed (gap MG-26, a toolchain defect). The test target
takes every file; `MetalUISDL` is a `condition: portable` dependency there
too. `SMK_UI_FREE=1` declares the old library shape, its exclude list plus
`SDLWindowTests.swift`. `swift-tools-version` stays 6.2. SwiftPM re-evaluated
the manifest when only the variable changed (`swift package describe` printed
the library shape under `SMK_UI_FREE=1` and the executable without it, and
the mutation below), so neither fallback in §2.1 was needed.

**`main.swift`.** `makeApp()`: `App()` on macOS; off macOS
`App(platform: try SDLPlatform(), textSystem: { PortableTextSystem(resolver:) })`
over `SystemFonts.resolver()` with `.monospaced` registered as "DejaVu Sans
Mono" (Linux) or "Consolas" (Windows), gap MG-25. `WindowMetrics.toolbarStripHeight`
(39 off macOS, 0 on macOS) is inside `chromeHeight`; the `windowMetrics`
test reads it.

**Tests.** `everyModeDraws` is `#if os(macOS)`. New
`SDLWindowTests.everyModeDrawsInAnSDLWindow` (`#if !os(macOS) &&
canImport(MetalUISDL)`, suite `.enabled(if: SMK_RUN_SDL_WINDOW_TEST=1)`)
opens a hidden `SDLPlatform` window built as `makeApp()` builds it and walks
every rail mode, both macro sub-states and both schemes (14 draws). Where the
window presents frames it expects one frame per draw and the window's scheme
to follow; **under SDL's `offscreen` driver (MetalUI's image) `beginFrame()`
answers `nil` and no frame builds**, so there it proves only that the window
opens with the app's themes and sizes. The tree's build and layout on Linux
are covered by the headless `renderFrame` tests, which now compile there
(`ShellRenderTests.everyModeRendersHeadlessly`, `PaneRenderTests`,
`MacroPaneTests`).

**macOS after the lane** (`swift build` then `swift test`, this worktree):
`Build complete!`, 0 `error:`, 0 `warning:`; `Test run with 256 tests in 32
suites passed` (XCTest `Executed 0 tests`). The count is unchanged: the SDL
test is not compiled on macOS.

**Linux image** (OrbStack, aarch64, `swift-6.4-RELEASE`;
`metalui-portable` rebuilt from MetalUI `70ed000` read-only, all layers
cached; a derived image `smk-linux` = `FROM metalui-portable` + `apt-get
install --no-install-recommends libhidapi-dev fonts-dejavu-core` (those two
lines are the whole Dockerfile; lane 3 commits them as
`Scripts/ci/Dockerfile.linux`); the
worktree at `/work`, scratch paths on volume `smk-xp-build`):
- `swift build --scratch-path /build/app`: `Build complete! (16.41 secs)`, 0
  `error:`. The only warning is the existing pkg-config hint for `hidapi`
  (Ubuntu ships no plain `hidapi.pc`; the manifest links `hidapi-hidraw`).
- `swift test --scratch-path /build/app`: `Test run with 251 tests in 31
  suites passed` (XCTest `Executed 0 tests`), the SDL suite reported
  `skipped`. Against macOS's 256 in 32: the two `#if canImport(CoreBluetooth)`
  suites and `everyModeDraws` are compiled out, the skipped SDL suite counts.
  `BinaryFormatAgreementTests` skips (no `~/esp/SMK` in the image).
- `SMK_RUN_SDL_WINDOW_TEST=1 swift test --filter SDLWindow`: `Test run with
  1 test in 1 suite passed`; it printed `14 draws requested, 0 frames drawn,
  SDL_VIDEO_DRIVER=offscreen`.
- `timeout 5 /build/app/debug/SMKConfigurator`: exit **124** (still running
  when killed; startup only, the offscreen driver presents nothing).

**UI-free mutation** (`import MetalUI` added as line 1 of
`Model/ActionToken.swift`, in the Linux image, scratch path `/build/ui-free`):
`SMK_UI_FREE=1 swift build --build-tests` failed, `ActionToken.swift:1:8:
error: no such module 'MetalUI'`; then plain `swift build`, same scratch path,
mutation still in place: `Build complete! (26.81 secs)`. Reverted (`git diff`
clean on `Model/`), then `SMK_UI_FREE=1 swift build --build-tests`:
`Build complete!`, and `SMK_UI_FREE=1 swift test`: `Test run with 217 tests
in 21 suites passed`.

Windows was not touched (lane 3).

### Lane 2 (2026-10-08)

**What landed.** `Views/PlatformToolbar.swift` (new): `primaryShortcutModifier`
(`.command` on macOS, `.control` elsewhere, A7, gap MG-24); `FileCommand.all`,
the one table of file commands (title, `AppIcon`, shortcut, whether a divider
precedes it, action), with each entry's toolbar id (`file.<icon>`), plain title
(the accessibility label) and tooltip ("Save As (Ctrl+Shift+S)"); and the
toolbar (M1): six `navigation` icon buttons (`Image(bitmap, scale: 3, label:)`
from the bundled 48-pixel toolbar PNGs, i.e. 16 points, picked by the
environment's colour scheme; `fallbackLabel` text if a PNG is missing), each
with `.help`, then a `Toggle("Advanced")` and a `Picker("Appearance")` in
`.menu` style, both `automatic` (trailing). `installAppCommands` builds the
File menu by looping over the table. Titles, order and dividers are as
before; Save As is `[primary, .shift]`. `ContentView` ends its chain with
`.platformToolbar(editor:dialogs:colorScheme:)` inside `rootView`'s `Column`
(`MD-S`), reading `@Environment(\.colorScheme)`.
**One departure from step 3's wording:** the toolbar *builder*
(`fileToolbar`) compiles on every platform. Only its use is compiled out:
`platformToolbar` is `self` under `#if os(macOS)`. That lets the macOS suite
check the toolbar half of the table too. The macOS app draws no toolbar, its
⌘ shortcuts are the same keys, and its menu has the same items. Nothing was
deleted.

**Tests** (`PlatformChromeTests`, 7, on all three platforms): the modifier
per platform; the table (six entries, titles, icons, dividers, primary
shortcuts, tooltip text); the File menu that `setMenuBar` receives is the
table in order, with its shortcuts and dividers; the toolbar that
`setToolbar` receives is the six buttons (each with an image and its plain
title), then the toggle and the `.menu` picker, matching the model; in a
window whose platform answers `false` to `setToolbar` (SDL's answer), a click
at (20, 19), the strip's first button, runs New; toolbar actions write
Advanced and Appearance; primary+N runs New through the command stage, and
off macOS Super+N does not. They run over a headless fake `Platform` in the
test file (no GPU, no SDL, no AppKit window; MG-17 status line). On macOS
the window's root is `ContentView` with `fileToolbar` applied by hand. Off
macOS it is the real `rootView`, so in the Linux image this suite is where
the strip lays out over the real shell: the offscreen SDL driver presents no
frame, so `SDLWindowTests` cannot see it (lane 1).
**Mutations** (macOS, this branch): (M1) the fake's `setToolbar` answering
`true`, so no strip is drawn, reddened `theStripsNewButtonRunsTheCommand`
(`fileURL == nil` failed). (M2) the `.keyboardShortcut(command.shortcut)`
line removed from `installAppCommands` reddened `menuBarReadsTheTable`
(shortcuts) and `primaryShortcutRunsNew`. Both were reverted.

**macOS** (`swift build` then `swift test`, this worktree): `Build complete!`,
0 `error:`, 0 `warning:`; `Test run with 263 tests in 33 suites passed`
(XCTest `Executed 0 tests`) = 256 + the 7 new tests.
`BinaryFormatAgreementTests` ran and passed (`~/esp/SMK` present). Launch: the
app ran 6 seconds with the screen unlocked and was killed (exit 143, SIGTERM,
no output). Not looked at; nothing visible was meant to change.

**Linux image** (`smk-linux`, aarch64, worktree at `/work`, scratch path
`/build/app` on `smk-xp-build`):
- `swift build`: `Build complete! (12.19 secs)`, 0 `error:` (only the
  existing hidapi pkg-config hint).
- `swift test`: `Test run with 258 tests in 32 suites passed` (251 + 7; the
  SDL suite skipped; XCTest `Executed 0 tests`).
- `SMK_RUN_SDL_WINDOW_TEST=1 swift test --filter SDLWindow`: `Test run with 1
  test in 1 suite passed`, `14 draws requested, 0 frames drawn,
  SDL_VIDEO_DRIVER=offscreen` (unchanged; the strip is not drawn there).
- `timeout 5 /build/app/debug/SMKConfigurator`: exit **124**.

**Review fix: the UI-free shape.** As first committed, lane 2 broke §2.1's
check: `PlatformChromeTests.swift` imports MetalUI but was not in the UI-free
test target's `exclude:` list, so `SMK_UI_FREE=1 swift build --build-tests`
failed on every platform (`PlatformChromeTests.swift:2:8: error: no such
module 'MetalUI'` in the Linux image). The lane's own runs had not included
the step. The file now joins the list, and lanes 2 and 3 now list the UI-free
build among their closing conditions. After the fix:
- macOS, scratch path `.build-uf`: `SMK_UI_FREE=1 swift build --build-tests`
  `Build complete! (17.06 sec)`; `SMK_UI_FREE=1 swift test` `Test run with
  222 tests in 23 suites passed` (XCTest `Executed 0 tests`). That is more
  than Linux's count because the two `#if canImport(CoreBluetooth)` suites
  compile here.
- Linux image, scratch path `/build/uf-l2fix`: `Build complete! (15.12
  secs)`; `Test run with 217 tests in 21 suites passed`, the same as lane 1.
- Default macOS shape, unchanged: `swift build` `Build complete!`; `swift
  test` `Test run with 263 tests in 33 suites passed`.

**Not verified.** How the strip looks (icon size against the 24-point
control row, the dark-scheme icons); a real Ctrl+S on a Linux or Windows
keyboard; the strip on Windows (lane 3). Gaps: no new entry. MG-23 and MG-24
record their workarounds as in place, and MG-17 gains a status line (a fake
`Platform` drives app input).

### Lane 3 (2026-10-08)

**What landed.** `.github/workflows/linux-build.yml` (§4.1: MetalUI cloned at
the revision `jq` reads from `Package.resolved`, its image built with the GHA
cache scoped by revision, `Scripts/ci/Dockerfile.linux` on top; `swift
build`, `swift test`, the UI-free build and tests on `/tmp/ui-free`, the
`timeout 5` launch expecting 124; then `Scripts/package-linux.sh` and a
launch of `dist/` in a fresh container that mounts **only** `dist/`).
`.github/workflows/windows-build.yml` (§4.2: `compnerd/gha-setup-swift@v0.5.0`
at `swift-6.4.0-release`, SDL 3.4.16's VC package (`lib\x64` on `PATH`), vcpkg
hidapi (its `bin` on `PATH`), `core.symlinks`, AccessKit flags from MetalUI's
script after `swift package resolve`, the three-attempt build, `swift build
--build-tests` + `swift test`, the UI-free build and tests on
`.build-ui-free`, the `SizeOfStackReserve` read-back with the toolchain's
`llvm-readobj`, the package, and a launch of the moved package). The 6.2
steps are gone from both. `Scripts/ci/Dockerfile.linux`,
`Scripts/package-linux.sh`, `Scripts/package-windows.ps1`, README, §5 above,
`dist/` in `.gitignore`. Nothing under `Sources/` or `Tests/` changed.

Two corrections to the plan, both measured: (1) under Swift 6.4's default
build system (swiftbuild) the resource bundle is
`SMKConfigurator_SMKConfigurator.bundle` on Linux and Windows too, not
`.resources` (§3 corrected; the scripts copy whichever exists). (2) The old
Windows retry loop read `$LASTEXITCODE` after `Start-Process`, which does not
set it, so it could never see a failure; the new loop calls `swift build`
directly, and evicts every `ModuleCache` under `.build` (swiftbuild keeps it
under `.build\out`).

**macOS** (this worktree, after the lane): `swift build` `Build complete!`,
0 `error:`; `swift test` `Test run with 263 tests in 33 suites passed`
(XCTest `Executed 0 tests`), unchanged from lane 2. UI-free shape,
scratch path `.build-uf`: `SMK_UI_FREE=1 swift build --build-tests`
`Build complete! (10.33 sec)`; `SMK_UI_FREE=1 swift test` `Test run with 222
tests in 23 suites passed`. `BinaryFormatAgreementTests` ran (`~/esp/SMK` present). Launch: the
`.build/debug/SMKConfigurator` ran 6 seconds with the screen unlocked and was
killed (exit 143, SIGTERM, no output).

**Linux image** (OrbStack, **aarch64**; CI is x86_64. `metalui-portable` as
lane 1 built it from MetalUI `70ed000`; `smk-linux` rebuilt from the
committed `Scripts/ci/Dockerfile.linux`; the worktree at `/work`. The
workflow's commands, with one local difference: scratch paths on the
`smk-xp-build` volume (`--scratch-path /build/l3-app`, `/build/l3-uf`,
`SCRATCH=/build/l3-pkg`) instead of `/work/.build`, so the macOS `.build` is
never touched. A worktree's `.git` file points at a host path, so `git
config` fails inside the mount; the workflow runs it from `/`):
- `swift build`: `Build complete! (25.33 secs)`, 0 `error:` (the existing
  hidapi pkg-config hint only).
- `swift test`: `Test run with 258 tests in 32 suites passed` (the SDL suite
  `skipped`; XCTest `Executed 0 tests`).
- `SMK_UI_FREE=1 swift build --build-tests`: `Build complete! (9.27 secs)`;
  `SMK_UI_FREE=1 swift test`: `Test run with 217 tests in 21 suites passed`.
- `timeout 5 …/debug/SMKConfigurator`: `launch exit 124`.
- `bash Scripts/package-linux.sh dist` (release): `dist/` = `MetalUISDLShaders`,
  `SMKConfigurator`, `SMKConfigurator_SMKConfigurator.bundle`. In a fresh
  container mounting only `dist/` at `/app` (`/build` absent): `moved launch
  exit 124`. **Separating arms**, same container shape: without
  `MetalUISDLShaders` the app stops at once (exit 133, `no compiled SDL
  shaders … in any of: /app/MetalUISDLShaders, /build/l3-pkg/checkouts/…`);
  without the resource bundle it stops at once (exit 133,
  `resource_bundle_accessor.swift:44: Fatal error: unable to find bundle named
  SMKConfigurator_SMKConfigurator`). So the 124 is the packaged copies at
  work, not the build tree.

**Windows VM** (UTM, Windows 11 **ARM64**, Swift 6.4.0
aarch64-unknown-windows-msvc; CI is x64. The VM was listed `stopped`; this
lane ran `utmctl start`. SSH did not answer for ~25 minutes and the guest
ignored an ACPI shutdown request (`utmctl stop --request`), so the lane
powered it off (`utmctl stop --force`) and started it again; SSH answered
3½ minutes later. `git config --global core.symlinks true` and
`core.longpaths true` set on the VM. The branch was cloned from a `git
bundle` copied to `C:\src\smk` (no push). SDL 3.4.16 `lib\arm64`
(`C:\src\SDL3-3.4.16`); AccessKit's ARM64 prebuilt fetched by MetalUI's
script into `C:\src\accesskit`; **hidapi**: no vcpkg on the VM and hidapi's
release zip has no ARM64 build, so hidapi 0.15.0's `windows/hid.c` was
compiled with the VS 2022 ARM64 `cl` into `C:\src\hidapi-arm64`
(`hidapi.dll` + import library). The workflow's commands with `arm64` paths,
in PowerShell 5.1 over SSH (`C:\src\smk-win.ps1`):
- `swift build`: `Build complete! (187.82 secs)`, exit 0 (warnings: no
  pkg-config, no `hidapi.pc`, as expected on Windows).
- `swift build --build-tests`: `Build complete! (79.49 secs)`; `swift test`:
  **`Test run with 258 tests in 32 suites passed`** (XCTest `Executed 0
  tests`; the SDL suite `skipped`). The executable target's tests link and
  run on Windows; the suites include `PlatformChromeTests` ("Menu, toolbar and
  shortcuts come from one table", passed), `IconLoaderTests`,
  `JSONFileStoreTests`, the two `MacroCapacity` suites, and
  `BinaryFormatAgreementTests` (skips: no `~/esp/SMK`).
- `SMK_UI_FREE=1 swift build --build-tests --scratch-path .build-ui-free`:
  `Build complete! (138.07 secs)`; `SMK_UI_FREE=1 swift test`: `Test run
  with 217 tests in 21 suites passed`.
- `llvm-readobj --file-headers` on the debug `SMKConfigurator.exe`:
  `Machine: IMAGE_FILE_MACHINE_ARM64 (0xAA64)`, **`SizeOfStackReserve:
  8388608`**.
- `Scripts\package-windows.ps1` (release): **the compiler asserted** in
  SILGen on `MacroStepEditor` (gap **MG-27**, a toolchain defect; also with
  lexical lifetimes off). With `-Configuration debug`: `Build complete!`,
  `dist` = `MetalUISDLShaders`, `SMKConfigurator_SMKConfigurator.bundle`,
  `hidapi.dll`, `SDL3.dll`, `SMKConfigurator.exe`.
- **Launch.** No user was logged in on the VM console after the restart
  (`query user`: none), so the interactive scheduled task could not run (it
  was registered, timed out and was unregistered) and **no screenshot was
  taken**. Over SSH (session 0), the packaged app moved to `C:\src\smk-dist`
  and with the build tree's `Shaders\compiled` renamed away got as far as
  claiming the window and stopped there: `Could not create swapchain! …
  (0x887A0022)`, the session-0 limit MetalUI's CLAUDE.md records. Separating
  arm: the same copy without `MetalUISDLShaders` stopped earlier, at `no
  compiled SDL shaders … in any of: C:/src/smk-dist-noshaders/MetalUISDLShaders,
  C:/src/smk/.build/…`. So on Windows the DLLs, fonts, resource bundle and
  packaged shaders all load; the window itself is unverified.
  `SDL_VIDEO_DRIVER=offscreen` does not help there (SDL's D3D12 device
  cannot claim an offscreen window). The build tree was restored after.
- This lane started the VM, so it shut Windows down from inside afterwards
  (`shutdown /s /t 0` over SSH); `utmctl status` read `stopped`.

**What ran where, against the workflows.** Linux: every command of
`linux-build.yml` ran in the image (scratch paths aside). Windows: every
command of `windows-build.yml` ran on the VM with ARM64 paths and a
hand-built hidapi instead of vcpkg x64, except two: the release package
(fails, MG-27; CI falls back to debug with a warning) and the final launch
step (session 0; the CI step is `continue-on-error` until it has passed
once). Not run anywhere: x64 Windows (the emulated route was not taken).

**Gaps.** MG-27 (new, medium, toolchain). No MetalUI change.


### Branch check (2026-10-08, `d67f1cd..c0fcc98`)

Independent re-runs, each on a fresh scratch path, of the code at `c0fcc98`
(the check's own commit changes only docs and the Linux workflow).

**macOS** (this worktree, `--scratch-path .build-checker`, created empty):
`swift build` `Build complete! (20.33 sec)`, exit 0; `swift test` `Test run
with 263 tests in 33 suites passed` (XCTest `Executed 0 tests`).
`BinaryFormatAgreementTests` ran (`~/esp/SMK` present). UI-free
(`.build-checker-uf`): `SMK_UI_FREE=1 swift build --build-tests` `Build
complete! (10.55 sec)`; `SMK_UI_FREE=1 swift test` `Test run with 222 tests
in 23 suites passed`. The app was not launched by the check.

**Linux image** (OrbStack, aarch64, `swift-6.4-RELEASE`; `metalui-portable`
rebuilt from `/Users/maxburger/Developer/MetalUI`, whose
`Backends/SDL/linux/` and `scripts/` are identical at `70ed000` and at that
checkout's `cd84b0c`; `smk-linux` rebuilt from `Scripts/ci/Dockerfile.linux`;
scratch paths `/build/c4b-chk-*` on `smk-xp-build`):
- `swift build`: `Build complete! (15.50 secs)`.
- `swift test`: `Test run with 258 tests in 32 suites passed` (the SDL suite
  `skipped`).
- `SMK_RUN_SDL_WINDOW_TEST=1 swift test --filter SDLWindow`: `Test run with
  1 test in 1 suite passed`, `14 draws requested, 0 frames drawn,
  SDL_VIDEO_DRIVER=offscreen`.
- UI-free: `Build complete! (8.35 secs)`; `Test run with 217 tests in 21
  suites passed`.
- `timeout 5 …/debug/SMKConfigurator`: `launch exit 124`.
- `package-linux.sh` (release): `Build complete! (50.00 secs)`, `dist` =
  `MetalUISDLShaders`, `SMKConfigurator`, `SMKConfigurator_SMKConfigurator.bundle`;
  launched from `/tmp`: exit 124; launched in a fresh container that mounts
  **only** that `dist` (`/build` absent): `moved launch exit 124`.
- **A first look at the Linux rendering.** The offscreen *video* driver
  presents no window frame, but MetalUI's public
  `SDLWindowRenderer(offscreenWidth:height:)` draws a `Scene` through SDL
  GPU into a texture and `readPixels()` returns it (how MetalUI's
  `DemoCapture` checks the demo). A throwaway test (not committed) built
  `rootView` with the public `renderFrame` over `SystemFonts` + DejaVu Sans
  Mono and the app's light theme overrides, at `WindowMetrics.idealSize`
  (1440 × 908, scale 1), and drew every rail mode with SDL's `vulkan` driver
  (Mesa lavapipe): 5 frames. Seen: the Adwaita rail icons, DejaVu text,
  the THM hex fields in DejaVu Sans Mono (the MG-25 workaround works), the
  macro library's search field in MetalUI's bordered chrome, nothing clipped
  in the KEY palette or the inspectors. Not seen this way: the toolbar strip
  (the window draws it; `renderFrame` does not), the dark scheme (MG-12),
  menus, alerts. This is the route `SDLWindowTests` could take in a later
  item to draw real pixels in CI.

**Windows VM** (UTM, ARM64, Swift 6.4.0; the VM was already running and was
left running; no user logged in on the console; the clone `C:\src\smk` was
already at `c0fcc98`; fresh scratch paths `C:\src\smk-chk-build` and
`C:\src\smk-chk-uf`; SDL 3.4.16 `lib\arm64`, the hand-built ARM64 hidapi
0.15.0 and AccessKit's ARM64 prebuilt, as lane 3):
- `swift build`: `Build complete! (1,293.19 secs)`, exit 0 (from empty).
- `swift build --build-tests`: `Build complete! (471.36 secs)`; `swift
  test`: **`Test run with 258 tests in 32 suites passed`**, the SDL suite
  `skipped`, `PlatformChromeTests` ("Menu, toolbar and shortcuts come from
  one table") passed — after 100 s, against well under a second on macOS
  and Linux: worth watching in CI time, not a failure.
- UI-free: `Build complete! (545.80 secs)`; `Test run with 217 tests in 21
  suites passed`.
- `llvm-readobj --file-headers`: `IMAGE_FILE_MACHINE_ARM64 (0xAA64)`,
  `SizeOfStackReserve: 8388608`.
- Not run by the check: the release package (MG-27, lane 3's finding
  stands), and any launch. The interactive scheduled-task route needs a
  logged-in console user and there was none, so **no screenshot of the
  Windows window exists**.

**CI YAML against MetalUI's own workflows.** Linux follows
`sdl-gpu-linux.yml` (same image, same `build-push-action` with GHA cache and
`load: true`, `docker run` with the repository at `/work`, `safe.directory`).
**Defect found and fixed:** the extra `smk-linux` layer was built with a
plain `docker build` after `setup-buildx-action`, whose docker-container
builder cannot see the loaded `metalui-portable`; reproduced locally with a
docker-container builder (`failed to resolve source metadata for
docker.io/library/metalui-portable:latest: pull access denied`), and the same
Dockerfile builds on the docker driver. The step now runs `docker buildx
build --builder default --load`. MetalUI never builds `FROM` its image, so it
has no such step. Windows follows MetalUI's Windows job (the same
`gha-setup-swift` pin, the same SDL VC package and `GITHUB_PATH`, the same
`fetch-accesskit.py --print-flags` route) and adds vcpkg hidapi,
`core.symlinks`, the UI-free build, the `/STACK` read-back, packaging and a
non-blocking launch; no defect found by reading. One comment claimed a
retry "has always passed", which nothing measured (the old loop could not
see a failure); reworded. Neither workflow has run on GitHub.

**Docs fixed by the check.** README's status table said tests and a launch
had run "in CI" (they ran in the local image and on the VM; CI has not run);
the gaps list's header named only the old pin; MG-27 called the old
Windows retry crash "very likely" the same defect without a measurement;
§4.1 now records the builder rule; §5.1 added; MG-28 added (the strip
height is internal).

**Verdict.** Mergeable after a first green CI run on GitHub: no code defect
found; macOS, the Linux image and the Windows VM all build and pass every
suite, and the UI-free shape holds on all three. Risks a person should
weigh: the first x64 Windows run is unproven (release build, the launch
step), and no human has seen the window on Linux or Windows.
