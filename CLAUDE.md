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

**Four-pane layout driven by one enum.** `RailMode` (`.key`/`.designs`/`.themes`/`.device`/`.macros`) selects which icon rail tab is active and drives what the list/main/inspector columns render — see the `switch editor.railMode` in each of `ContentView`'s three column properties. Design/theme editing happens inline (not in modal sheets): `ContentView` owns `designDraft`/`themeDraft` scratch copies that mirror the selected design/theme until explicitly saved, mimicking an edit-then-Save/Cancel flow without a sheet. `.macros` is the one rail mode with sub-states of its own: `MacroWorkspace` (`.library`/`.editor(id:)`) swaps the whole list/main/inspector layout between the macro library table and the step editor, because a macro is a document-within-the-document — opening one to edit it needs its own canvas and inspector, not just a different list selection — where every other rail mode renders one fixed layout regardless of what's selected.

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
- `firmwareVersionLabel` in `EditorState.swift` — a static label, must be bumped by hand when targeting a new firmware build. In particular, bump it for whichever firmware build first carries keymap-store **frame version 2** (`~/esp/SMK/Sources/SMKCore/KeymapFrame.swift`'s `frameVersion`) — the switch from the version-1 JSON payload to the binary payload documented below. The frame's own header (magic/version/length/CRC, same 11 bytes, same offset) is unchanged, so an upload aimed at frame-version-1 firmware fails the version check and is cleanly rejected rather than misread — but the label should already say "binary-capable" before that surprises anyone.
- `KeymapUploader.maxPayloadLength` — must match firmware's `SMK_KEYMAP_MAX_LEN`.
- `ActionToken`'s *grammar* (the `key:`/`mod:`/`mo:`/`tg:`/`trans`/`none`/`toggle_conn` prefixes) is hand-written and must match `KeyAction.fromCString` in the firmware's `LayerEngine.swift`; so must `ModifierName` against `Modifier.fromCString`. The *vocabulary* it dispatches into (`KeyName`) is generated — see `keycodes.json` below.
- `keycodes.json` (in `~/esp/SMK`) — **the** source of the key vocabulary for both repos. `Sources/SMKConfigurator/Model/KeyCodesGenerated.swift` is **generated** from it by `~/esp/SMK/generate_keycodes.sh`; do not edit it. Adding a key means editing the manifest and re-running the script, then committing the regenerated file in *both* repos. `KeyVocabularyTests` pins the agreement by comparing HID usages, not just names.
- `EditorState.maxLayerCount` — the firmware's layer ceiling (16), not an editor preference: `LayerEngine`'s `toggledLayers`/`momentaryCounts` are sized `count: 16` and `isLayerActive` rejects anything `>= 16`.
- `defaultKeymapURL` (`EditorState.swift`) points at `~/esp/SMK/keymap.json` — the reference file this app is pointed at by default.
- `Sources/SMKConfigurator/Device/BLEUploadUUIDs.swift` — **generated**, do not edit. The custom GATT upload service's UUIDs, produced together with the firmware's `Sources/components/smk_ble_uuids.h` by `~/esp/SMK/generate_ble_uuids.sh` from `~/esp/SMK/ble_upload_uuids.json`. Regenerate in both repos and commit both. `BLEUploadUUIDsTests` pins the values.
- **Macros** (`Model/Macro.swift`) are carried in `keymap.json` under an
  optional top-level `"macros"` array and uploaded with the layers. None of
  this exists on the firmware side yet (see
  `docs/superpowers/specs/2026-08-20-macro-creation-design.md`, sub-project
  3). A firmware author implementing the macro player needs all of the
  following — not just the byte-width table in `MacroStep.compiledSize`'s
  doc comment, which omits the opcode values, endianness, bit packing, and
  keycode derivation a byte-for-byte implementation needs:

  - **JSON schema.** A macro is `{ "id": Int, "name": String, "steps": [...] }`.
    Each step object has a `"t"` field selecting its shape (`CodingKeys` in
    `MacroStep` names every JSON field below, since they otherwise appear
    nowhere but that enum):
    - `{"t":"key","k":"key:<name>","mods":["leftShift",...],"hold":<ms>}` —
      `"k"` is optional (a modifiers-only chord omits it) and reuses the
      `key:` string `ActionToken` already parses, naming a `KeyName`.
    - `{"t":"text","s":"<string>","delivery":"keystrokes"|"paste","cpm":<msPerChar>}`
      — `"delivery"` defaults to `"keystrokes"` when absent.
    - `{"t":"delay","ms":<ms>}`
    - `{"t":"layer","op":"mo"|"tg","n":<layer index>}`
    - `{"t":"rpt","count":<n>,"steps":[...]}` — does not nest; a `"rpt"`
      whose own `"steps"` contains another `"rpt"` is invalid, and the
      editor preserves it unexecuted rather than running it.
    A step whose `"t"` is unrecognized, or whose known fields don't resolve
    in this build (an unknown key name, an unrecognized modifier anywhere in
    `"mods"`, an unrecognized `"delivery"`/`"op"`), round-trips through the
    editor unexecuted rather than being dropped or silently normalized —
    `MacroStep.raw`. A per-macro field this build doesn't know (e.g. a
    future `"enabled"`) round-trips the same way.

  - **Bytecode layout and opcodes.** The layout is `MacroStep.compiledSize`'s
    doc comment; the opcode byte each step's `"t"` compiles to is only
    defined here:

    | step | opcode | layout |
    |---|---|---|
    | keystroke | `0x01` | `opcode(1) + mods(1) + keycode(1) + holdMs(2)` = 5 |
    | delay | `0x02` | `opcode(1) + ms(2)` = 3 |
    | layer | `0x03` | `opcode(1) + op(1) + index(1)` = 3 |
    | text | `0x04` | `opcode(1) + delivery(1) + msPerChar(1) + length(1) + payload` = 4 + n |
    | repeat | `0x05` | `opcode(1) + count(1) + bodyLength(2) + body` = 4 + body |

    A compiled macro is `id(1) + nameLength(1) + name + stepCount(1) + steps`.
    All multi-byte fields (`holdMs`, `ms`, `bodyLength`) are **little-endian**
    — the native byte order of both supported MCUs (RP2040 is Cortex-M0+,
    ESP32-C6 is RISC-V; both little-endian), so neither port needs a
    byte-swap.

  - **`mods` bit packing.** `ModifierName`'s eight cases, in their
    `CaseIterable` declaration order (`leftCtrl, leftShift, leftAlt,
    leftGUI, rightCtrl, rightShift, rightAlt, rightGUI`), are bits 0–7 of
    the `mods` byte, LSB first. That is the same order and layout as the
    modifier byte of a standard USB HID keyboard report, so a firmware
    `mods` byte can be OR'd directly into a HID report rather than remapped.

  - **`keycode` derivation.** `keycode(1)` is `KeyName.hidUsage`
    (`KeyCodesGenerated.swift`) — the same HID usage ID sent in a keyboard
    report. `0x00` (HID "no key") when a keystroke step has no `"k"`.

  - **`delivery` byte.** `0x00` = `"keystrokes"` (type each character),
    `0x01` = `"paste"`. This byte exists precisely so the editor's
    keystrokes/paste toggle has somewhere to land on the wire; a layout
    without it would make that toggle a UI-only no-op.

  - **`op` byte.** `0x00` = `"mo"` (momentary), `0x01` = `"tg"` (toggle).

  - **One-byte field maxima.** `length`, `nameLength`, `stepCount`,
    `count` (repeat), `msPerChar` (text), `id` (macro header), and `index`
    (layer) are each one byte, so a text payload, a macro name, a macro's
    top-level step count, a repeat count, a text step's ms-per-char, a
    macro's slot id, and a layer step's target layer each cap at 255
    (UTF-8 bytes for the first two). The editor enforces this on its side
    via `MacroStep.overflows` / `MacroDefinition.overflows`
    (`MacroDefinition.isCompilable` is the all-clear check), consulted in
    `EditorState.sendToDevice()` alongside the compiled-bytecode capacity
    guard and the JSON-size guard — any macro with a nonempty `overflows`
    blocks the upload and surfaces `MacroOverflow.message` before a
    transport is ever touched. UI sliders keep the editor itself from
    producing an overflowing value, but a hand-edited or decoded
    `keymap.json` isn't bound by the UI, which is why this is checked again
    at upload time rather than trusted from the editing surface — firmware
    should still reject rather than silently truncate if a real board ever
    receives one anyway.

  `ActionToken`'s `macro:N` token now compiles too (`KeymapCellTag.macro`,
  see the binary payload bullet below) — it is no longer missing a
  firmware-side implementation.

- **The wire/storage format is compiled binary; `keymap.json` on disk stays
  JSON.** This is a different contract from the JSON macro-step schema
  documented above: that schema is what `keymap.json` holds on disk (still
  plain JSON, always lossless — see `KeymapDocument`/`ActionToken`'s `.raw`
  fallback). `Model/KeymapCompiler.swift`'s `compileKeymap(_:)` is what
  turns a whole `KeymapDocument` — matrix, every layer's cells, every macro
  — into the byte payload that actually reaches a board: a 6-byte header
  (`rowCount`, `colCount`, `colsAreDriven`, `layerCount`, `macroCount`,
  reserved), the row/col GPIO arrays, then every cell of every layer as a
  two-byte `(tag, parameter)` pair (`KeymapCellTag`), then each macro
  (`id(1) + nameLength(1) + name + stepCount(1) + steps`, opcodes/layout as
  already documented above). Compiling is not lossless the way saving is: a
  token with no binary tag (`ActionToken.raw`), or a parameter over its
  wire field's range (a macro slot over 255, a layer at or past
  `EditorState.maxLayerCount`), makes `compileKeymap` throw
  `KeymapCompileError` naming the offending token and its layer/row/column
  rather than truncating, wrapping, or silently dropping it — refusing to
  flash a token the firmware could never have executed anyway.

  **Three independent implementations must agree on this format, and
  changing one without the others silently breaks uploads or storage:**
  this compiler (`Model/KeymapCompiler.swift`), the firmware's decoder
  (`~/esp/SMK/Sources/SMKCore/KeymapBinary.swift`), and the firmware's
  `~/esp/SMK/generate_default_keymap.sh` (which compiles the reference
  `keymap.json` into a literal Swift array at build time, using the same
  tag layout, so the compiled-in factory-reset default agrees too).

  **`CAPS`** (opcode `0x05` on the existing BEGIN/CHUNK/COMMIT/ERASE
  transport — `~/esp/SMK/Sources/SMKCore/KeymapProtocol.swift`'s
  `smkKeymapOpCaps`) exists on both sides now: `Device/DeviceTransport.swift`'s
  `KeymapUploader.queryCapacity(using:)` sends it and decodes the
  little-endian response (`macroBytes` u16, `macroSlots` u8, `keymapMaxLen`
  u16); `EditorState.applyDeviceCapacity(_:deviceKey:)` adopts the result —
  `macroCapacity`/`macroCapacitySource = .device` — and persists it under
  `deviceKey` (`"usb"`, or `"ble:<peripheral name>"`, the best device
  identity this app currently has) so a later session with nothing
  connected reports `.lastKnown` instead of dropping back to
  `MacroCapacity.floor`. Two of `CAPS`'s numbers look like bugs and are
  deliberate on the firmware side — see `DeviceCapacityReport`'s doc
  comment in `DeviceTransport.swift` for why: `macroBytes` equals
  `keymapMaxLen` (macros share the layers' payload budget rather than
  having a separate region of their own), and `macroSlots` maxes out at
  255, not 256 (the macro id space is a full byte, but the wire field
  reporting its size is also one byte and cannot itself represent 256).
  `MacroCapacity.floor` remains what the editor assumes before any board
  has ever answered `CAPS` — a deliberate under-promise, not a target.

When editing model/device code, check whether the change needs a matching change on the firmware side (or vice versa) before assuming it's editor-only.

## Platform-conditional code

Three places branch on OS, each for a different reason — know which one you're touching before assuming a pattern generalizes:
- `Package.swift` — resource bundling (`iconResources`) is chosen via a top-level `#if os(...)` *variable*, not `.when(platforms:)` on `Resource.copy()`, because that overload doesn't exist and Swift disallows `#if` inside an array literal.
- `Package.swift` linker settings — `hidapi` is linked under different library names per platform (`hidapi` on macOS, `hidapi-hidraw` on Linux, `hidapi` again via vcpkg on Windows) because `pkgConfig` resolution silently fails on both Ubuntu and Windows for different root causes (see the inline comments there before changing this).
- `Views/AppIcon.swift` (`IconLoader`) — picks an icon's platform folder at compile time (`#if os(macOS/Windows)`/else→Linux) and its light/dark folder at runtime (`@Environment(\.colorScheme)`). Icon PNGs are pre-rendered and checked in (`Sources/SMKConfigurator/Resources/{macOS,Windows,Linux}/Icons/`), not generated at build time — rerun `Scripts/generate-icons.sh` (requires `rsvg-convert` via `brew install librsvg`, plus Xcode CLT for the SF Symbols step) after changing the icon set.
- `Device/BLETransport.swift` — the entire file is `#if canImport(CoreBluetooth)`-gated; on platforms without it, `sendToDevice()` falls straight to `DeviceTransportError.noDeviceFound` after a failed USB attempt.

## Design/plan docs

Nontrivial features go through a spec-then-plan process under `docs/superpowers/`: a design doc in `specs/` (problem, design overview, numbered implementation pieces, testing notes) followed by a plan in `plans/` with the same date-prefixed filename. Check there for the rationale behind a subsystem before re-deriving it from code — e.g. `2026-08-05-platform-native-icons-design.md` explains why icons are pre-rendered PNGs rather than live symbol lookups, `2026-08-01-hidapi-usb-transport-design.md` explains the hidapi transport choice over IOKit.
