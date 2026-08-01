# hidapi-based USB Transport (Cross-Platform USB Path)

Date: 2026-08-01
Status: Approved, pending implementation plan

## Problem

`USBRawHIDTransport` (added in the runtime-keymap-updates feature, `Sources/SMKConfigurator/Device/USBRawHIDTransport.swift`) talks to the RP2040 build's raw HID upload interface via IOKit's `IOHIDManager` — a macOS-only API. The goal is to make the USB device-upload path work on Linux (and, in principle, Windows) too, using `hidapi` (https://github.com/libusb/hidapi), a cross-platform C library for USB HID access.

Out of scope: `BLETransport` (CoreBluetooth) stays macOS-only — there is no cross-platform equivalent for BLE within the same API, and porting BLE to other platforms (bluez on Linux, WinRT on Windows) is a separate, much larger project for later, if ever needed. This spec covers only the USB/RP2040 path.

Also out of scope: actually running the rest of `smk_configurator` (the SwiftCrossUI-based editor UI) on Linux. This spec's Linux verification is scoped to proving the app *builds* on Linux (SwiftCrossUI's own `DefaultBackend` already resolves to its GTK backend there) with the hidapi-based transport linked in — not to shipping or testing a full Linux app experience.

## Design overview

Three pieces:

1. **`CHidapi` system-library target** — an SPM system-library wrapping the installed `hidapi` C library, with platform-specific linking (Homebrew on macOS, apt's split packages on Linux).
2. **Rewritten `USBRawHIDTransport`** — same `DeviceTransport` conformance and external contract as today, internals swapped from `IOHIDManager` to `hidapi`'s `hid_open`/`hid_read_timeout`/`hid_write`/`hid_close`, with blocking reads moved onto a dedicated background thread.
3. **Linux CI workflow** — a new GitHub Actions job that installs Swift + `libhidapi-dev` (+ SwiftCrossUI's own GTK build dependencies, since `DefaultBackend` needs them to compile there regardless of this change) and runs `swift build` on `ubuntu-24.04`.

## 1. `CHidapi` system-library target

A new target in `Package.swift`:

```swift
.systemLibrary(name: "CHidapi", pkgConfig: "hidapi", providers: [
    .brew(["hidapi"]),
    .apt(["libhidapi-dev"]),
])
```

with `Sources/CHidapi/module.modulemap` and `Sources/CHidapi/shim.h` (a `#include <hidapi/hidapi.h>` — the header path hidapi installs under on both Homebrew and apt).

**Known platform-naming risk, to be resolved during implementation, not guessed here:** Homebrew's `hidapi` formula and Debian/Ubuntu's `libhidapi-dev` package historically expose their pkg-config module(s) under different names — Homebrew tends to ship a single unified `hidapi.pc`, while Debian-family distros commonly split into `hidapi-hidraw.pc` and `hidapi-libusb.pc` with no plain `hidapi.pc`. If a single `pkgConfig: "hidapi"` doesn't resolve on Linux, the systemLibrary target's `pkgConfig` value (or a platform-conditional fallback via explicit `linkerSettings` with `.linkedLibrary(_:.when(platforms:))` in the `SMKConfigurator` executable target instead of relying on `pkgConfig` alone) will need adjusting once the actual CI run reveals what's installed. Do not guess further than this in the plan — verify against the real Linux CI output.

## 2. `USBRawHIDTransport` rewrite

Same external shape as today (conforms to `DeviceTransport`, `init() throws`, `func send(_ packet: [UInt8]) async throws -> [UInt8]`), same VID/PID/usage-page matching (`0x16C0`/`0x05DF`, vendor page `0xFF00`, usage `0x01`) — `hidapi` supports opening by VID/PID directly (`hid_open`), and usage-page filtering via `hid_enumerate` + inspecting each `hid_device_info`'s `usage_page`/`usage` fields to pick the right interface, mirroring what the IOKit matching dictionary did.

Reads: `hid_read` has no callback/notification model (unlike `IOHIDManagerRegisterInputReportCallback`), so:
- Open the device once in `init`.
- `send(_:)` calls `hid_write`, then reads the response by dispatching a blocking `hid_read_timeout` call (bounded, e.g. 1s per attempt, looped with a cancellation check) onto a dedicated background thread, bridging the result back via a `withCheckedThrowingContinuation` — matching the same external async contract `KeymapUploader` already expects, no caller-visible change.
- `deinit` closes the device handle (`hid_close`) and, if this is the last open `USBRawHIDTransport`, calls `hid_exit()` — mirroring the `init`-time `hid_init()` call. (hidapi requires a paired `hid_init`/`hid_exit`; a simple reference count or a single call at process lifetime is acceptable — decide the exact approach during implementation once the class's actual lifecycle is visible.)

## 3. Linux CI workflow

New file: `.github/workflows/linux-build.yml`. Modeled directly on SwiftCrossUI's own Linux CI job (found in the vendored `swift-cross-ui` package checkout, `.github/workflows/build-test-and-docs.yml`'s `linux` job), which already proves what SwiftCrossUI's `DefaultBackend` needs to build on Linux:

```yaml
name: Linux Build

on:
  push:
    branches: [main]
  pull_request:

jobs:
  linux:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v3

      - name: Install Swift
        uses: SwiftyLab/setup-swift@latest
        with:
          swift-version: "6.1.0"

      - name: Install dependencies
        run: |
          sudo apt update
          sudo apt install -y libgtk-4-dev libgtk-3-dev clang libhidapi-dev

      - name: Build
        run: swift build
```

This proves the whole package (including `SMKConfigurator`'s executable target, which pulls in `CHidapi` and SwiftCrossUI's `DefaultBackend`) compiles on Linux. It does not run the test suite headlessly (that would need `xvfb`, matching SwiftCrossUI's own pattern) since this workflow's job is build verification, not full app testing — running the existing `swift test` suite (the pure-logic `KeymapUploadProtocol`/`KeymapUploader` tests, which have no device or UI dependency) can be added as a follow-up if useful, but is not required for this spec's goal.

## Testing

- **macOS**: existing behavior preserved — `swift build`/`swift test` continue to pass (27/27), `USBRawHIDTransport`'s new hidapi-based internals verified by code review (no hardware in this environment either way, same limitation as the IOKit version had).
- **Linux**: the new CI workflow is the verification — a real `ubuntu-24.04` runner building the whole package with hidapi + SwiftCrossUI's GTK backend installed. No RP2040 hardware is available for either platform to test actual device communication; both remain code-review-verified until real hardware testing happens (same caveat as the rest of the device-upload feature).
