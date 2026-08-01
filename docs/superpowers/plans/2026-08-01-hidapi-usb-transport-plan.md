# hidapi USB Transport Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `USBRawHIDTransport`'s macOS-only IOKit implementation with `hidapi` (cross-platform C library), and add CI to prove the whole package builds on Linux.

**Architecture:** A new `CHidapi` SPM system-library target wraps the installed `hidapi` C library (Homebrew on macOS, apt on Linux). `USBRawHIDTransport` is rewritten against `hidapi`'s `hid_enumerate`/`hid_open_path`/`hid_write`/`hid_read_timeout`/`hid_close` — same `DeviceTransport` conformance and external async contract as before, so `KeymapUploader` and `EditorState.sendToDevice()` need no changes. A new GitHub Actions workflow builds the package on `ubuntu-24.04`.

**Tech Stack:** Swift 6 (SPM `systemLibrary` target), hidapi 0.15+ (C library), GitHub Actions.

## Global Constraints

- `BLETransport`/CoreBluetooth stays untouched — this plan covers the USB/RP2040 path only.
- `USBRawHIDTransport`'s public contract is unchanged: `final class USBRawHIDTransport: DeviceTransport`, `init() throws`, `func send(_ packet: [UInt8]) async throws -> [UInt8]`. No caller (`KeymapUploader`, `EditorState`) is touched.
- VID/PID/usage-page matching stays the same: vendor ID `0x16C0`, product ID `0x05DF`, usage page `0xFF00`, usage `0x01` — matching `ports/rp2040/platform/usb_descriptors.c` in the sibling firmware repo.
- **Deviation from the design spec, discovered while grounding this plan in the real `hidapi.h` header (verified against the actual installed Homebrew copy, `/opt/homebrew/Cellar/hidapi/0.15.0/include/hidapi/hidapi.h`):** the spec's async-read design proposed a persistent background thread with a manual cancellation-checked polling loop around `hid_read_timeout`. That's unnecessary — `hid_read_timeout` already takes its own bounded timeout and returns 0 on timeout, 1 blocking call is sufficient. The simpler design below (one `queue.async` block per `send(_:)` call, doing write-then-read synchronously within it) replaces that section of the spec.
- **Real hidapi calling-convention detail, not in the spec, discovered from the header's doc comments:** `hid_write`'s first data byte is always a Report ID slot — `0x0` for devices (like this one) that don't use numbered reports — even though the actual USB wire packet is still exactly `KeymapUploadProtocol.packetLength` (32) bytes. The code below prepends/strips this byte; which hidapi backends echo it back on read is a genuine platform inconsistency that can't be fully verified without real hardware — the code handles both cases defensively (see Task 1, Step 2's comments) and this must be specifically checked during hardware testing (Task 11 of the sibling runtime-keymap-updates plan, or a dedicated follow-up).
- `hid_exit()` is intentionally never called (only `hid_init()`, in `init()`) — matching common hidapi usage: `hid_exit()` tears down library-global state meant for final process shutdown, not safe to call per-transport-instance if another instance could still be relying on the library being initialized.

---

### Task 1: CHidapi system-library target + rewritten USBRawHIDTransport

**Files:**
- Create: `Sources/CHidapi/module.modulemap`
- Create: `Sources/CHidapi/shim.h`
- Modify: `Package.swift`
- Modify: `Sources/SMKConfigurator/Device/USBRawHIDTransport.swift` (full rewrite)

**Interfaces:**
- Consumes: `DeviceTransport`, `DeviceTransportError` (`Sources/SMKConfigurator/Device/DeviceTransport.swift`, unchanged), `KeymapUploadProtocol.packetLength` (unchanged).
- Produces: `final class USBRawHIDTransport: DeviceTransport` — identical public shape to before (`init() throws`, `func send(_ packet: [UInt8]) async throws -> [UInt8]`).

- [ ] **Step 1: Add the `CHidapi` system-library target**

Create `Sources/CHidapi/module.modulemap`:

```
module CHidapi [system] {
    header "shim.h"
    link "hidapi"
    export *
}
```

Create `Sources/CHidapi/shim.h`:

```c
#include <hidapi/hidapi.h>
```

Modify `Package.swift` — add the system-library target and wire it into `SMKConfigurator`'s dependencies, removing the now-unused `IOKit` linker framework (confirmed via `grep -rl "import IOKit" Sources/` that `USBRawHIDTransport.swift` — rewritten in Step 2 below — is the only consumer):

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SMKConfigurator",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/stackotter/swift-cross-ui", .upToNextMinor(from: "0.8.0"))
    ],
    targets: [
        .systemLibrary(
            name: "CHidapi",
            pkgConfig: "hidapi",
            providers: [
                .brew(["hidapi"]),
                .apt(["libhidapi-dev"]),
            ]
        ),
        .executableTarget(
            name: "SMKConfigurator",
            dependencies: [
                .product(name: "SwiftCrossUI", package: "swift-cross-ui"),
                .product(name: "DefaultBackend", package: "swift-cross-ui"),
                "CHidapi",
            ],
            linkerSettings: [
                .linkedFramework("CoreBluetooth"),
            ]
        ),
        .testTarget(
            name: "SMKConfiguratorTests",
            dependencies: ["SMKConfigurator"]
        ),
    ]
)
```

**Note on the `pkgConfig: "hidapi"` name:** confirmed correct for Homebrew (verified directly: `/opt/homebrew/Cellar/hidapi/0.15.0/lib/pkgconfig/hidapi.pc` exists and `pkg-config --cflags --libs hidapi` resolves cleanly to `-I.../include/hidapi -L.../lib -lhidapi`). This is **not yet verified for apt's `libhidapi-dev`** — Debian/Ubuntu's hidapi packaging has historically split into `hidapi-hidraw.pc`/`hidapi-libusb.pc` with no plain `hidapi.pc`. If Task 2's Linux CI run fails specifically at the `swift build` step with a pkg-config resolution error (not a compile error), that confirms this — the fix is changing `pkgConfig: "hidapi"` to `pkgConfig: "hidapi-hidraw"` (prefer the hidraw backend over libusb on Linux: no separate libusb runtime dependency, and this is a fixed-VID/PID vendor HID interface, not an isochronous/bulk-transfer device where libusb's extra control would matter). Do not guess further than this without real CI output in hand.

- [ ] **Step 2: Rewrite `USBRawHIDTransport.swift`**

Replace the entire file:

```swift
import CHidapi
import Foundation

/// Talks to the RP2040 build's raw HID upload interface (vendor usage page
/// 0xFF00, usage 0x01 — see ports/rp2040/platform/usb_descriptors.c in the
/// SMK firmware repo) via hidapi, a cross-platform USB/BLE HID library —
/// this keeps the USB path portable to Linux/Windows, unlike the
/// macOS-only IOKit HID Manager it replaces.
final class USBRawHIDTransport: DeviceTransport {
    private static let vendorID: UInt16 = 0x16C0
    private static let productID: UInt16 = 0x05DF
    private static let usagePage: UInt16 = 0xFF00
    private static let usage: UInt16 = 0x01

    private let device: OpaquePointer
    private let queue = DispatchQueue(label: "USBRawHIDTransport")

    init() throws {
        hid_init()

        // hid_open(vid, pid, nil) opens the first matching device, which
        // isn't precise enough here: this VID/PID also matches the
        // keyboard's own boot-HID interface. Enumerate and match on usage
        // page/usage (mirrors the IOKit matching dictionary this
        // replaces), then open the matched device by its path.
        guard let list = hid_enumerate(Self.vendorID, Self.productID) else {
            throw DeviceTransportError.noDeviceFound
        }
        defer { hid_free_enumeration(list) }

        var matchedPath: String?
        var current: UnsafeMutablePointer<hid_device_info>? = list
        while let info = current {
            if info.pointee.usage_page == Self.usagePage, info.pointee.usage == Self.usage,
               let path = info.pointee.path {
                matchedPath = String(cString: path)
                break
            }
            current = info.pointee.next
        }

        guard let path = matchedPath, let opened = hid_open_path(path) else {
            throw DeviceTransportError.noDeviceFound
        }
        device = opened
    }

    deinit {
        hid_close(device)
    }

    func send(_ packet: [UInt8]) async throws -> [UInt8] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [device] in
                // hid_write's calling convention always expects a leading
                // Report ID byte, 0x0 for devices (like this one) that
                // don't use numbered reports — see hidapi.h's hid_write
                // doc comment. The actual on-the-wire USB packet is still
                // exactly KeymapUploadProtocol.packetLength (32) bytes;
                // this leading 0x00 is purely hidapi's buffer convention.
                var writeBuffer = [UInt8](repeating: 0, count: packet.count + 1)
                writeBuffer[1...] = packet[...]
                let written = writeBuffer.withUnsafeBufferPointer { ptr in
                    hid_write(device, ptr.baseAddress, ptr.count)
                }
                guard written == writeBuffer.count else {
                    continuation.resume(throwing: DeviceTransportError.noDeviceFound)
                    return
                }

                // Symmetric leading-byte handling on read: some hidapi
                // backends echo a leading report-ID placeholder in the
                // read buffer, others don't (a known platform
                // inconsistency — verify against real hardware). Always
                // return exactly the last packet.count bytes actually
                // read, regardless of which case this turns out to be.
                var readBuffer = [UInt8](repeating: 0, count: packet.count + 1)
                let readCount = readBuffer.withUnsafeMutableBufferPointer { ptr in
                    hid_read_timeout(device, ptr.baseAddress, ptr.count, 1000)
                }
                guard readCount > 0 else {
                    continuation.resume(throwing: DeviceTransportError.noDeviceFound)
                    return
                }
                let response = Array(readBuffer[max(0, readCount - packet.count)..<readCount])
                continuation.resume(returning: response)
            }
        }
    }
}
```

- [ ] **Step 3: Verify it builds on macOS**

Run: `swift build`
Expected: succeeds. `hidapi` is already installed on this machine via Homebrew (confirmed: `brew list hidapi` shows it present), so no extra local setup should be needed. If `pkg-config hidapi` somehow isn't found, run `brew install hidapi` first.

- [ ] **Step 4: Verify existing tests still pass**

Run: `swift test`
Expected: 27/27 passing, same as before this change (this task adds no new tests — there's no hardware in this environment to test a real device round-trip against, same limitation the IOKit version had).

- [ ] **Step 5: Commit**

```bash
git add Sources/CHidapi/module.modulemap Sources/CHidapi/shim.h Package.swift Sources/SMKConfigurator/Device/USBRawHIDTransport.swift
git commit -m "Replace IOKit-based USBRawHIDTransport with cross-platform hidapi"
```

---

### Task 2: Linux CI workflow

**Files:**
- Create: `.github/workflows/linux-build.yml`

**Interfaces:**
- Consumes: nothing code-level — this is a CI configuration file that builds the package produced by Task 1.
- Produces: a GitHub Actions workflow that runs on push/PR to `main`.

- [ ] **Step 1: Write `.github/workflows/linux-build.yml`**

Modeled directly on `swift-cross-ui`'s own Linux CI job (`.build/checkouts/swift-cross-ui/.github/workflows/build-test-and-docs.yml`'s `linux` job — the same Swift-version pin and GTK packages that job uses to build `DefaultBackend` on Linux, which this package also depends on):

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

      - name: Swift version
        run: swift --version

      - name: Install dependencies
        run: |
          sudo apt update
          sudo apt install -y libgtk-4-dev libgtk-3-dev clang libhidapi-dev

      - name: Build
        run: swift build
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/linux-build.yml
git commit -m "Add Linux CI build to verify the hidapi-based USB transport"
```

- [ ] **Step 3: Push and watch the first run**

This is the actual Linux verification this whole plan exists for — a local `swift build` on macOS cannot prove the package builds on Linux. Push the branch (or merge to `main`, per whatever workflow this repo uses) and check the Actions run.

If it fails at `swift build` with a message mentioning `hidapi.pc` not found (pkg-config resolution), apply the fallback from Task 1 Step 1's note: change `Package.swift`'s `pkgConfig: "hidapi"` to `pkgConfig: "hidapi-hidraw"`, commit, and push again.

If it fails for any other reason (a real compile error in `USBRawHIDTransport.swift` under Linux's Glibc/Foundation, or a GTK-related failure unrelated to this change), that's a real issue to diagnose against the actual CI log output — do not guess a fix without seeing it.
