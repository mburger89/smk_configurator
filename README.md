# SMK Configurator

A desktop app for editing keymaps and pushing them to a keyboard running the
[SMK](https://github.com/mburger89/SMK) firmware. Edit layers and key actions,
author macros, arrange the physical layout, theme it, and upload over USB or
Bluetooth — without rebuilding or reflashing firmware.

The UI is built with [MetalUI](https://github.com/mburger89/MetalUI), a
GPU-accelerated Swift UI framework with SwiftUI's vocabulary. **The same app
runs on macOS, Linux and Windows**: AppKit and Metal on macOS, MetalUI's SDL3
backend (with its portable text system and AccessKit for screen readers) on
Linux and Windows.

## Status

| Platform | UI | Tests | Bluetooth | USB |
|---|---|---|---|---|
| macOS | AppKit + Metal | `swift test`, every suite | yes (CoreBluetooth) | hidapi |
| Linux | SDL3 + Vulkan: built, tested, and the app and a packaged copy started under SDL's offscreen driver, in MetalUI's CI image on aarch64 | `swift test` (and the UI-free tests) in the image; the CI workflow (x86_64) has not run yet | **no** | hidapi (hidraw) |
| Windows | SDL3 + Direct3D 12: built, tested and packaged on an ARM64 VM; release builds hit a compiler assertion there, so the package is a debug build (gap MG-27) | `swift test` (and the UI-free tests) on the ARM64 VM; the CI workflow (x64) has not run yet | **no** | hidapi |

Nobody has looked at the Linux or Windows window yet: on Linux an agent can
only start it under SDL's offscreen driver, which presents no frame, and on
the Windows VM a window needs a logged-in console session, which there was
not. The GitHub workflows have not run: they first run when the branch is
pushed. What is left for a person to check, per platform, is listed in
`docs/superpowers/2026-10-08-metalui-cross-platform-plan.md` §5.

The app was ported from SwiftCrossUI to MetalUI on macOS first
(`docs/superpowers/2026-10-06-metalui-port-plan.md`), then brought to Linux
and Windows (`docs/superpowers/2026-10-08-metalui-cross-platform-plan.md`).
What MetalUI could not express, and the workaround used for each, is in
`docs/superpowers/2026-10-06-metalui-gaps.md`.

### What Linux and Windows lack

- **Bluetooth.** BLE upload uses CoreBluetooth, so it is macOS-only. The
  Device pane shows only the USB card, and "Send to Device" without a USB
  board reports that no device was found.
- **A menu bar.** MetalUI draws no menu bar on SDL. The File and View menus
  are replaced by a toolbar strip across the top of the window: New, Open,
  Save, Save As, Import and Export as icon buttons, then an **Advanced**
  toggle and an **Appearance** menu. Shortcuts use **Ctrl** instead of ⌘
  (Ctrl+N, Ctrl+O, Ctrl+S, Ctrl+Shift+S). There is no Quit or Close shortcut:
  close the window.
- **Title bar colour.** The window's title bar follows the system theme, not
  View ▸ Appearance; the content follows the setting.
- Menus, pickers and alerts are drawn in the window instead of being native.
  File dialogs are native (on Linux they need `xdg-desktop-portal` or
  `zenity`; without either, opening a file reports an error).

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
menu; **View** holds Advanced Mode and Appearance (Light / Dark / System). On
Linux and Windows both are in the toolbar strip at the top of the window.

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

**Linux: let your user open the board.** hidapi's hidraw backend opens
`/dev/hidraw*`, which is root-only by default; without a rule the Device pane
reads "Not connected" with the board plugged in. As root, write
`/etc/udev/rules.d/70-smk.rules`:

```
# SMK keyboard (RP2040 build), raw HID upload interface
KERNEL=="hidraw*", ATTRS{idVendor}=="16c0", ATTRS{idProduct}=="05df", TAG+="uaccess"
```

then `sudo udevadm control --reload-rules && sudo udevadm trigger`, and replug
the board.

## Building

Every platform needs a **Swift 6.4** toolchain (MetalUI's manifest) and
hidapi. MetalUI is pinned to one revision in `Package.swift`; move the pin
deliberately (change `revision:`, then `swift package update`).

### macOS

`brew install hidapi`, then:

```bash
swift build
swift run SMKConfigurator
swift test
```

To run it as a real `.app` bundle (icon, Info.plist, the Bluetooth usage
string CoreBluetooth needs): `bash Scripts/run.sh`. That wraps
`swift-bundler` with `Bundler.toml`. Whether swift-bundler copies MetalUI's
shader bundle (`MetalUI_MetalUIRender.bundle`) into `Contents/Resources` is
unverified; if the bundled app fails at launch with
`ShaderLibraryError.resourceMissing`, use the recipe in MetalUI's
`docs/packaging.md` instead. `swift run` is unaffected.

### Linux

You need, on the compiler's default paths (`/usr` or `/usr/local`):

- **SDL3 3.4 or later**, built with X11 and/or Wayland. Use your
  distribution's `libsdl3-dev` where it is 3.4+, or build SDL with its
  defaults. (MetalUI's CI image builds SDL offscreen-only: fine for building
  and testing, but it opens no window on a desktop.)
- **AccessKit's C bindings**: from a MetalUI checkout,
  `sudo python3 Backends/SDL/scripts/fetch-accesskit.py --prefix /usr/local`
  (prebuilt on x86_64; built with cargo on aarch64).
- **hidapi**: `libhidapi-dev` (the hidraw backend), plus the udev rule above.
- **A font**: any installed family works through fontconfig; DejaVu
  (`fonts-dejavu-core`) gives the monospaced fields DejaVu Sans Mono.

```bash
swift build
swift run SMKConfigurator
swift test
```

`bash Scripts/package-linux.sh` builds a release and lays out a movable
`dist/`: the executable, its resource bundle, and MetalUI's compiled SDL
shaders (`MetalUISDLShaders`). SDL3 and hidapi still come from the system.

CI builds and tests inside MetalUI's own Linux image (Swift 6.4, SDL3,
AccessKit) plus `Scripts/ci/Dockerfile.linux`; the same two files reproduce
it locally:

```bash
# from a MetalUI checkout at the pinned revision:
docker build -t metalui-portable -f Backends/SDL/linux/Dockerfile Backends/SDL
# from this repository:
docker build -t smk-linux -f Scripts/ci/Dockerfile.linux Scripts/ci
docker run --rm -v "$PWD":/work -w /work smk-linux swift test
```

Inside that image `swift run SMKConfigurator` starts and keeps running but
shows nothing: the image's SDL uses the offscreen video driver. (The
container shares the mounted `.build` with the host, so on a Mac give it its
own `--scratch-path`.)

### Windows

- **SDL3 3.4 or later**: `SDL3-devel-3.4.16-VC.zip` from SDL's releases.
- **hidapi**: `vcpkg install` (this repository's `vcpkg.json`).
- **AccessKit**: after `swift package resolve`, run
  `python .build\checkouts\MetalUI\Backends\SDL\scripts\fetch-accesskit.py --print-flags`;
  it prints the SwiftPM flags that reach the library.
- Clone with symlinks on (`git config --global core.symlinks true`): MetalUI's
  shader header is a git symlink.

No pkg-config on Windows, so every path is a flag:

```powershell
$sdl = "C:\path\to\SDL3-3.4.16"; $hid = "vcpkg_installed\x64-windows"
$flags = @("-Xcc", "-I$sdl\include", "-Xswiftc", "-L$sdl\lib\x64",
           "-Xcc", "-I$hid\include", "-Xswiftc", "-L$hid\lib") +
         @(python .build\checkouts\MetalUI\Backends\SDL\scripts\fetch-accesskit.py --print-flags)
swift build @flags
swift test @flags
```

At run time `SDL3.dll` and `hidapi.dll` must be on `PATH` or beside the
executable. `Scripts\package-windows.ps1 -SwiftFlags $flags -DllDirs "$sdl\lib\x64","$hid\bin"`
lays out a movable `dist\` with both DLLs, the resource bundle and the
shaders. Add `-Configuration debug` where `-c release` trips Swift 6.4.0's
Windows compiler assertion (gap MG-27; seen on ARM64). The executable
reserves an 8 MB main-thread stack (`/STACK`, in `Package.swift`): Windows' default 1 MB is too small for the window's layout.

### The model without the UI

`SMK_UI_FREE=1` makes `Package.swift` declare `SMKConfigurator` as a library
over `Model/` and `Device/` only, with MetalUI not declared at all. CI builds
and tests it on Linux and Windows on its own scratch path; a `Model/` or
`Device/` file that imports MetalUI or names a view fails it:

```bash
SMK_UI_FREE=1 swift build --build-tests --scratch-path .build-ui-free
SMK_UI_FREE=1 swift test --scratch-path .build-ui-free
```

The test files that import MetalUI or test views are excluded in that shape
(see the comment in `Package.swift`).

There is no macOS workflow.

## Layout

```
Sources/SMKConfigurator/
  Model/       document, actions, macros, designs, themes, persistence, app state
  Device/      transports and the upload protocol
  Views/       MetalUI UI, grouped by rail mode, over shared pieces
               (Palette.swift: the chrome colours as light/dark theme keys)
  main.swift   the App (AppKit or SDL), the window, the menu bar
  Resources/<Platform>/Icons   each platform's own icon set (only that one is bundled)
Scripts/       run-as-bundle wrapper, icon generation, Linux/Windows packaging,
               ci/Dockerfile.linux (the Linux CI image's extra layer)
docs/superpowers/
  2026-10-06-metalui-port-plan.md   how the SwiftCrossUI build was ported
  2026-10-08-metalui-cross-platform-plan.md   Linux and Windows on SDL
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
