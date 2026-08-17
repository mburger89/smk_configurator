# SMK Configurator

A cross-platform desktop app for editing keymaps and pushing them to a keyboard
running the [SMK](https://github.com/mburger89/SMK) firmware. Edit layers and key
actions, arrange the physical layout, theme it, and upload over USB or Bluetooth
— without rebuilding or reflashing firmware.

Built with [SwiftCrossUI](https://github.com/stackotter/swift-cross-ui), so it is
one Swift codebase for macOS, Windows, and Linux rather than three native
front-ends.

## What it does

The window is four panes driven by an icon rail with four modes:

| Mode | What it edits |
|---|---|
| **Key** | The keymap — layers, and the action bound to each key |
| **Designs** | The physical layout: key sizes, gaps, and the matrix's GPIO wiring |
| **Themes** | Colours and styling (cosmetic; the firmware never sees these) |
| **Device** | Connection status and uploading |

A keymap is a `keymap.json` matching the firmware's schema exactly. Key actions
are raw strings — `key:a`, `mo:1`, `tg:2`, `trans`, `none` — and anything the UI
doesn't specifically recognise is preserved rather than dropped, so saving a file
is always lossless even against a newer firmware's vocabulary.

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
sent — the firmware's matrix stays compiled in.

BLE is macOS-only in practice: `BLETransport.swift` is gated on CoreBluetooth
being available, and on other platforms a failed USB attempt reports no device
rather than falling through.

## Building

```bash
swift build --target SMKConfigurator --build-system native
swift run   --build-system native SMKConfigurator
swift test  --build-system native                        # 42 tests in 10 suites
```

**Both flags are load-bearing.** They look like noise and they are not:

- `--target SMKConfigurator` — a bare `swift build` compiles every target in the
  dependency graph, including SwiftCrossUI's Windows-only backend, which cannot
  build on macOS or Linux.
- `--build-system native` — needed whenever your toolchain resolves through
  Xcode, as this repo's `.swift-version` arranges. SwiftPM's newer default build
  system eagerly plans SwiftCrossUI's Android-only shim target and fails on a
  missing `android/log.h`. Installing the Android NDK does **not** fix this — it
  just moves the failure to the link step. The target has to not be planned at
  all, which is what this flag achieves.

To run it as a real `.app` bundle rather than a bare executable:

```bash
bash Scripts/run.sh
```

That wrapper exists because `swift-bundler` shells out to `swift build` itself
and hits the same problem, and there is nowhere to record the flag permanently.
Use it instead of calling `swift-bundler` directly.

macOS is the only platform actually runnable from a normal development machine
here. Windows and Linux are compile-verified through GitHub Actions — build only,
no test step.

## Layout

```
Sources/SMKConfigurator/
  Model/       document, actions, designs, themes, persistence, app state
  Device/      transports and the upload protocol
  Views/       UI, grouped by rail mode, over shared chrome primitives
Scripts/       run-as-bundle wrapper, icon generation
```

`EditorState` is the single observable model — document, file I/O, uploads,
designs and themes, and UI state all live on it, installed once and read from the
environment everywhere.

## Firmware coupling

This app is written against a specific firmware version and has no way to ask a
running board what it is. Several values are pinned by hand and must be changed
in step with the firmware:

- `firmwareVersionLabel` — currently `v0.8.0`, a static label
- `KeymapUploader.maxPayloadLength` — 4085, must match the firmware's
  `smkKeymapMaxLen`
- `ActionToken`'s cases — must match the firmware's action/keycode vocabulary
- `EditorState.maxLayerCount` — 16, a firmware ceiling rather than a preference

When changing anything in `Model/` or `Device/`, check whether the firmware needs
a matching change.

## Related

- [SMK](https://github.com/mburger89/SMK) — the firmware this edits keymaps for.
- [SMK Test Board](https://github.com/mburger89/SMK_test_board) — a 3×3 macropad
  for validating both ends on real hardware.
