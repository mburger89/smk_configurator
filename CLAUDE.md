# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A cross-platform (macOS/Windows/Linux) desktop GUI, built with [SwiftCrossUI](https://github.com/stackotter/swift-cross-ui), for editing and uploading keymaps to the [SMK](../SMK) custom keyboard firmware. It edits `keymap.json` (layers of key actions) and pushes it to a connected keyboard over USB raw HID (RP2040 builds) or BLE HID-over-GATT (ESP32-C6 builds). This is the *editor*; the firmware itself lives in the sibling `~/esp/SMK` repo, which this app's model types are kept byte-for-byte compatible with (see "Firmware coupling" below).

## Commands

```bash
swift build --target SMKConfigurator --build-system native   # build (see notes below on both flags)
swift run --build-system native SMKConfigurator               # run the app
swift test --build-system native                              # run all tests
swift test --build-system native --filter <SuiteOrTestName>   # run one suite/test
bash Scripts/run.sh                     # run as a real .app bundle (swift-bundler + Bundler.toml)
bash Scripts/generate-icons.sh          # regenerate bundled icon PNGs (see Views/AppIcon.swift)
```

**Always scope builds/runs to `--target SMKConfigurator`, never a bare `swift build`.** A bare build compiles every target in the full dependency graph, including swift-cross-ui's Windows-only `swift-winui` backend, which fails on macOS/Linux (needs Windows SDK headers). CI (`.github/workflows/*.yml`) does the same scoping.

**`--build-system native` is required on a toolchain resolved via Xcode(-beta)** (i.e. whenever `.swift-version` selects `xcode` or `xcode-select`/`DEVELOPER_DIR` points at an Xcode install, as this repo's `.swift-version`/`.vscode/settings.json` do) — SwiftPM's new default build system (`swiftbuild`) eagerly plans swift-cross-ui's full dependency graph even when scoped with `--target`, hitting its Android-only `AndroidBackendShim` target (`android/log.h` not found on macOS). swift-cross-ui's `Package.swift` already disables that target when it detects it's being driven by Xcode's build system, but its detection only checks for a parent process literally named `xcodebuild`/`Xcode` — `swiftbuild` invoked directly via the CLI slips past that check. `--build-system native` (deprecated but functional) routes around the same limitation the upstream check exists for. Not needed with a non-Xcode toolchain (e.g. swiftenv-managed, or CI's `SwiftyLab/setup-swift`/`compnerd/gha-setup-swift`, neither of which resolves through Xcode).

`swift-bundler` shells out to `swift build` itself, so a bare `swift-bundler run`/`bundle` hits the exact same `android/log.h` failure — it needs the flag forwarded, one `--Xswiftpm` per token: `--Xswiftpm --build-system --Xswiftpm native`. There's nowhere to put that permanently (swift-bundler 3.0 has no Bundler.toml key or env var for default SwiftPM arguments, and SwiftPM has no `SWIFTPM_BUILD_SYSTEM`), hence the `Scripts/run.sh` wrapper — use it rather than calling `swift-bundler` directly.

Installing the Android NDK does **not** fix any of this, so don't go down that path: with the header satisfied, `AndroidBackendShim` compiles for `arm64-apple-macos` and the macOS link then fails on `Undefined symbols: ___android_log_write` (it lives in Android's `liblog.so`, which has no macOS counterpart). The target has to not be planned at all, which is exactly what `--build-system native` achieves.

macOS is the only platform actually runnable/verifiable from a normal dev machine here; Windows and Linux are compile-verified only, via GitHub Actions (`linux-build.yml`, `windows-build.yml` — both build-only, no test step, no local reproduction path for either).

## Architecture

**MVVM with a single observable model.** `EditorState` (`Model/EditorState.swift`) is the one `@ObservableObject` for the whole app — document state, file I/O, device upload, design/theme management, and UI state (drawer height, selected key, appearance mode) all live on it as plain stored properties (no `didSet`, since `@ObservableObject` skips properties with accessors — mutating helper methods persist to `UserDefaults` explicitly instead, e.g. `setDrawerHeight(_:)`, `setAppearanceMode(_:)`). It's installed once in `App.swift` via `.environment(editor)` and read everywhere via `@Environment(EditorState.self)`.

**Four-pane layout driven by one enum.** `RailMode` (`.key`/`.designs`/`.themes`/`.device`) selects which icon rail tab is active and drives what the list/main/inspector columns render — see the `switch editor.railMode` in each of `ContentView`'s three column properties. Design/theme editing happens inline (not in modal sheets): `ContentView` owns `designDraft`/`themeDraft` scratch copies that mirror the selected design/theme until explicitly saved, mimicking an edit-then-Save/Cancel flow without a sheet.

**Model layer** (`Model/`):
- `KeymapDocument` — mirrors the firmware's `keymap.json` schema exactly (`LayerEngine.loadKeymap` in the SMK repo). Cells are raw strings (`"key:a"`, `"mo:1"`, `"trans"`, `"none"`, etc.), not a parsed enum, so save is always lossless even for tokens the UI doesn't specifically render.
- `ActionToken` — the parsed/typed view of one cell string, matching the firmware's `KeyAction`/`KeyCode`/`Modifier` `fromCString` vocabulary. Unrecognized strings become `.raw(String)` rather than being dropped.
- `KeyboardDesign` — an editor-only concept (the firmware never sees it): physical layout (key widths, gaps) plus the matrix electrical config (`matrix.rows`/`cols` GPIO numbers, `colsAreDriven`) needed to write a valid `keymap.json`.
- `KeyboardTheme` — cosmetic only, has no firmware-side counterpart.
- `JSONFileStore<T>` — generic one-file-per-item JSON persistence shared by designs and themes, under `~/Library/Application Support/SMKConfigurator/{Designs,Themes}`.

**Device layer** (`Device/`): `DeviceTransport` is a two-method protocol (`send(_:) async throws -> [UInt8]`) with two implementations — `USBRawHIDTransport` (hidapi, matches RP2040 builds' vendor usage page 0xFF00/usage 0x01) and `BLETransport` (CoreBluetooth), which talks to the firmware's **custom upload GATT service** (`BLEUploadUUIDs`) rather than the HID service — macOS hides HID-over-GATT from Core Bluetooth apps entirely, so the old vendor HID Report ID 2 channel was unreachable and was removed firmware-side (`BleHelper.swift`'s comment records this). Report ID 1 is the keyboard; Report ID 2 is now unused. `KeymapUploader` drives the same BEGIN/CHUNK×N/COMMIT protocol over either transport — transport-agnostic by design. `EditorState.sendToDevice()` tries USB first, then falls back to BLE. Matrix data is never sent; firmware's matrix stays compiled-in.

**Views** (`Views/`) are grouped by rail mode (`KeyModeViews`, `DesignModeViews`, `ThemeModeViews`, `DeviceModeViews`) plus shared chrome (`TitlebarView`, `StatusBarView`, `IconRailView`, `UIStyle`). `UIStyle.swift` defines the shared `Chrome`/`TapTarget`/`RailButton`/`ToolbarPill` primitives every pane's controls are built from.

## Firmware coupling

This app is written against a specific version of `~/esp/SMK` and several places encode that coupling explicitly rather than reading it dynamically (the app has no way to query a running firmware's version):
- `firmwareVersionLabel` in `EditorState.swift` — a static label, must be bumped by hand when targeting a new firmware build.
- `KeymapUploader.maxPayloadLength` — must match firmware's `SMK_KEYMAP_MAX_LEN`.
- `ActionToken`'s *grammar* (the `key:`/`mod:`/`mo:`/`tg:`/`trans`/`none`/`toggle_conn` prefixes) is hand-written and must match `KeyAction.fromCString` in the firmware's `LayerEngine.swift`; so must `ModifierName` against `Modifier.fromCString`. The *vocabulary* it dispatches into (`KeyName`) is generated — see `keycodes.json` below.
- `keycodes.json` (in `~/esp/SMK`) — **the** source of the key vocabulary for both repos. `Sources/SMKConfigurator/Model/KeyCodesGenerated.swift` is **generated** from it by `~/esp/SMK/generate_keycodes.sh`; do not edit it. Adding a key means editing the manifest and re-running the script, then committing the regenerated file in *both* repos. `KeyVocabularyTests` pins the agreement by comparing HID usages, not just names.
- `EditorState.maxLayerCount` — the firmware's layer ceiling (16), not an editor preference: `LayerEngine`'s `toggledLayers`/`momentaryCounts` are sized `count: 16` and `isLayerActive` rejects anything `>= 16`.
- `defaultKeymapURL` (`EditorState.swift`) points at `~/esp/SMK/keymap.json` — the reference file this app is pointed at by default.
- `Sources/SMKConfigurator/Device/BLEUploadUUIDs.swift` — **generated**, do not edit. The custom GATT upload service's UUIDs, produced together with the firmware's `Sources/components/smk_ble_uuids.h` by `~/esp/SMK/generate_ble_uuids.sh` from `~/esp/SMK/ble_upload_uuids.json`. Regenerate in both repos and commit both. `BLEUploadUUIDsTests` pins the values.

When editing model/device code, check whether the change needs a matching change on the firmware side (or vice versa) before assuming it's editor-only.

## Platform-conditional code

Three places branch on OS, each for a different reason — know which one you're touching before assuming a pattern generalizes:
- `Package.swift` — resource bundling (`iconResources`) is chosen via a top-level `#if os(...)` *variable*, not `.when(platforms:)` on `Resource.copy()`, because that overload doesn't exist and Swift disallows `#if` inside an array literal.
- `Package.swift` linker settings — `hidapi` is linked under different library names per platform (`hidapi` on macOS, `hidapi-hidraw` on Linux, `hidapi` again via vcpkg on Windows) because `pkgConfig` resolution silently fails on both Ubuntu and Windows for different root causes (see the inline comments there before changing this).
- `Views/AppIcon.swift` (`IconLoader`) — picks an icon's platform folder at compile time (`#if os(macOS/Windows)`/else→Linux) and its light/dark folder at runtime (`@Environment(\.colorScheme)`). Icon PNGs are pre-rendered and checked in (`Sources/SMKConfigurator/Resources/{macOS,Windows,Linux}/Icons/`), not generated at build time — rerun `Scripts/generate-icons.sh` (requires `rsvg-convert` via `brew install librsvg`, plus Xcode CLT for the SF Symbols step) after changing the icon set.
- `Device/BLETransport.swift` — the entire file is `#if canImport(CoreBluetooth)`-gated; on platforms without it, `sendToDevice()` falls straight to `DeviceTransportError.noDeviceFound` after a failed USB attempt.

## Design/plan docs

Nontrivial features go through a spec-then-plan process under `docs/superpowers/`: a design doc in `specs/` (problem, design overview, numbered implementation pieces, testing notes) followed by a plan in `plans/` with the same date-prefixed filename. Check there for the rationale behind a subsystem before re-deriving it from code — e.g. `2026-08-05-platform-native-icons-design.md` explains why icons are pre-rendered PNGs rather than live symbol lookups, `2026-08-01-hidapi-usb-transport-design.md` explains the hidapi transport choice over IOKit.
