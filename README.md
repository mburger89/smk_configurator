# SMK Configurator

A desktop app for editing keymaps and pushing them to a keyboard running the
[SMK](https://github.com/mburger89/SMK) firmware. Edit layers and key actions,
author macros, arrange the physical layout, theme it, and upload over USB or
Bluetooth — without rebuilding or reflashing firmware.

The UI is built with [MetalUI](https://github.com/mburger89/MetalUI), a
GPU-accelerated Swift UI framework with SwiftUI's vocabulary. **The app runs on
macOS today.** The keymap model and device code also build on Linux and
Windows (and test on Linux), with no UI dependency; a Linux/Windows UI on MetalUI's SDL backend
is a later, separate step.

## Status

| Platform | UI | Model and device code |
|---|---|---|
| macOS | the MetalUI app (`swift run SMKConfigurator`) | built and tested (`swift test`) |
| Linux | pending — waits on MetalUI's SDL backend | built and tested in CI |
| Windows | pending — waits on MetalUI's SDL backend | built, tests compiled (not run) in CI |

The app was ported from SwiftCrossUI to MetalUI in one step; how, and every
deliberate difference from the previous build, is in
`docs/superpowers/2026-10-06-metalui-port-plan.md`. What MetalUI could not
express, and the workaround used for each, is in
`docs/superpowers/2026-10-06-metalui-gaps.md`.

## What it does

The window is four panes driven by an icon rail with five modes:

| Mode | What it edits |
|---|---|
| **Keymap** | The keymap — layers, and the action bound to each key (drag a chip from the palette onto a key, or click a chip to assign it to the selected key) |
| **Designs** | The physical layout: key sizes, gaps, and the matrix's GPIO wiring |
| **Themes** | Colours and styling (cosmetic; the firmware never sees these) |
| **Device** | Connection status and uploading |
| **Macros** | A library of macros (search, collections, enable/disable, import/export) and a step editor: keystrokes, typed text, delays, layer switches and repeat blocks, with the board's memory budget shown as you go |

File actions (New, Open, Save, Save As, Import, Export) are in the **File**
menu; **View** holds Advanced Mode and Appearance (Light / Dark / System).

A keymap is a `keymap.json` matching the firmware's schema exactly. Key actions
are raw strings — `key:a`, `mo:1`, `tg:2`, `trans`, `none`, `macro:3` — and
anything the UI doesn't specifically recognise is preserved rather than
dropped, so saving a file is always lossless even against a newer firmware's
vocabulary.

Designs and themes are editor-only concepts, stored one JSON file per item under
your platform's application-support directory.

## Uploading

`DeviceTransport` is a two-method protocol with two implementations, and the
uploader drives the same BEGIN / CHUNK×N / COMMIT exchange over either:

- **USB raw HID** via hidapi — vendor usage page `0xFF00`, usage `0x01`. This is
  how RP2040 builds are reached.
- **BLE** via CoreBluetooth, through a custom GATT service. ESP32-C6 builds are
  reached this way.

Upload tries USB first and falls back to BLE. The matrix configuration is never
sent — the firmware's matrix stays compiled in. BLE is macOS-only:
`BLETransport.swift` is gated on CoreBluetooth being available.

## Building

Requires a **Swift 6.4** toolchain on macOS (MetalUI's manifest) and hidapi
(`brew install hidapi`).

```bash
swift build
swift run SMKConfigurator
swift test
```

No extra flags. `Package.swift` declares the target per platform:

- **macOS** — `SMKConfigurator` is the app (an executable over `Model/`,
  `Device/`, `Views/` and `main.swift`), depending on MetalUI, pinned to one
  revision. Move the pin deliberately: change `revision:`, then
  `swift package update`.
- **Linux, Windows** — `SMKConfigurator` is a library over `Model/` and
  `Device/` only; MetalUI is not even declared. That build is what keeps the
  model free of UI types. The test files that import MetalUI or test views are
  excluded there (see the comment in `Package.swift`).

CI: the Linux workflow builds the library and runs its tests (Swift 6.2,
`libhidapi-dev`); the Windows workflow builds it and its tests. There is no
macOS workflow.

To run it as a real `.app` bundle (icon, Info.plist, the Bluetooth usage string
CoreBluetooth needs):

```bash
bash Scripts/run.sh
```

That wraps `swift-bundler` with `Bundler.toml`. Its `--build-system native`
flag dates from SwiftCrossUI and is not needed for MetalUI; whether
swift-bundler copies MetalUI's shader bundle (`MetalUI_MetalUIRender.bundle`)
into `Contents/Resources` is unverified — if the bundled app fails at launch
with `ShaderLibraryError.resourceMissing`, use the recipe in MetalUI's
`docs/packaging.md` instead. `swift run` is unaffected.

## Layout

```
Sources/SMKConfigurator/
  Model/       document, actions, macros, designs, themes, persistence, app state
  Device/      transports and the upload protocol
  Views/       MetalUI UI, grouped by rail mode, over shared pieces
               (Palette.swift: the chrome colours as light/dark theme keys)
  main.swift   the App, the window, the menu bar
Scripts/       run-as-bundle wrapper, icon generation
docs/superpowers/
  2026-10-06-metalui-port-plan.md   how the SwiftCrossUI build was ported
  2026-10-06-metalui-gaps.md        what MetalUI could not express, and the
                                    app-side workaround used for each
```

`EditorState` is the single `@Observable` model — document, file I/O, uploads,
designs, themes, macros and UI state all live on it. One instance is created in
`main.swift` and passed to every view (`let editor: EditorState`). Views are
MetalUI `Component`s written in its layout vocabulary (`Row`/`Column`/`Box`,
`Pixels`); app colours are MetalUI palette keys (`ThemeColorKey`) with light
and dark values, so the whole window follows the colour scheme.

## Firmware coupling

This app is written against a specific firmware version and has no way to ask a
running board what it is. Several values are pinned by hand and must be changed
in step with the firmware:

- `firmwareVersionLabel` — currently `v0.9.0`, a static label
- `KeymapUploader.maxPayloadLength` — 4085, must match the firmware's
  `smkKeymapMaxLen`
- `ActionToken`'s cases — must match the firmware's action/keycode vocabulary
- `EditorState.maxLayerCount` — 16, a firmware ceiling rather than a preference
- `Model/KeyCodesGenerated.swift` and `Device/BLEUploadUUIDs.swift` — generated
  by scripts in the firmware repo; do not edit by hand

When changing anything in `Model/` or `Device/`, check whether the firmware needs
a matching change.

## Related

- [SMK](https://github.com/mburger89/SMK) — the firmware this edits keymaps for.
- [SMK Test Board](https://github.com/mburger89/SMK_test_board) — a 3×3 macropad
  for validating both ends on real hardware.
- [MetalUI](https://github.com/mburger89/MetalUI) — the UI framework.
