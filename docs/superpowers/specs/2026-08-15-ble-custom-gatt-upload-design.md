# BLE Custom GATT Upload Service (ESP32-C6)

Date: 2026-08-15
Status: Approved, pending implementation plan

This feature spans both repos. The spec lives here, in `smk_configurator`;
the firmware half it governs is in the sibling `~/esp/SMK` repo (paths below
are written out in full for that reason). Implementation of the firmware
pieces should leave a pointer to this file in `~/esp/SMK/docs/superpowers/`.

## Problem

`BLETransport` cannot upload a keymap to an ESP32-C6 board from macOS, and no
amount of fixing on the app side alone will change that. Two independent
blockers, both confirmed against real hardware on 2026-08-15 (a Seeed XIAO
ESP32-C6 running `my_swift_keyboard.bin` at firmware `f2a92bb`):

1. **The firmware never advertises the HID service UUID.**
   `start_advertising()` (`~/esp/SMK/Sources/components/ble_helper.c:66`) sets
   flags, name, and appearance (`0x03C1`) but never populates
   `fields.uuids16`. `BLETransport.connect()` scans
   `withServices: [CBUUID(string: "1812")]`, which matches only against
   advertised service UUIDs, so it discovers nothing. A scan with that exact
   filter returned 0 peripherals while an unfiltered scan in the same run saw
   the board as `SMK Keyboard` at rssi -35 with `advertised services: none`.

2. **macOS hides the HID service from Core Bluetooth.** Connecting to the
   board by name and enumerating GATT returns `["1813", "180F", "180A"]`
   (Scan Parameters, Battery, Device Information) — the HoGP companion
   services — with `0x1812` absent. Apple reserves HID-over-GATT for the
   system HID stack, so the Report characteristic `0x2A4D` and the
   `0x2908` Report Reference descriptors that `BLETransport` walks to find
   the Report ID 2 in/out pair are unreachable from an ordinary app. Fixing
   blocker 1 alone yields a connection and then a dead end.

The fix is to stop carrying keymap traffic over HID at all and give the
upload channel its own 128-bit GATT service, which Core Bluetooth will
happily expose. This is the BLE analogue of what the RP2040 build already
does on USB, where the vendor usage page `0xFF00` exists precisely so the OS
does not claim the interface.

### Out of scope

- The upload protocol itself. BEGIN/CHUNK/COMMIT/ERASE framing, the 32-byte
  packet size, the 28-byte chunk payload, and the CRC32 are unchanged, so
  `SMKCore/KeymapProtocol.swift`, `KeymapUploadProtocol.swift`, and the
  RP2040 raw-HID path stay byte-identical. A larger MTU would cut a ~4 KB
  upload from ~146 round trips to ~20, but it would fork the shared dispatch
  code for a few seconds of wall time. Not worth it.
- The RP2040/USB transport, and the nRF52840 and STM32WB ports.
- Running the configurator's BLE path anywhere but macOS. `BLETransport` is
  already `#if canImport(CoreBluetooth)`-gated and stays that way.

## Design overview

Phase 1 is the implementable unit and everything below describes it unless
marked otherwise. Phase 2 (§9) is scoped here because it shares the same
NimBLE security surface, but it gets its own plan.

1. Fixed service and characteristic UUIDs, shared by both repos.
2. Firmware: register a custom GATT service in `ble_helper.c`.
3. Firmware: re-lay the advertisement so the service UUID fits.
4. Firmware: remove the Report ID 2 channel.
5. App: rewrite `BLETransport` discovery and I/O.
6. App: real BLE status and upload progress.
7. Error handling.
8. Testing.
9. Phase 2: encryption, persistent bonding, multi-host reconnect.

## 1. UUIDs

| Role | UUID |
|---|---|
| Upload service | `DA227673-007D-4BE6-A602-BC27421945FC` |
| Packet write (host → device) | `3A877283-CAFD-4716-8671-148B32475E97` |
| Response notify (device → host) | `C975356B-1B48-4871-A8A6-FB1155381A8F` |

These are fixed constants in both repos and must be kept in sync by hand, the
same way `KeymapUploader.maxPayloadLength` and `ActionToken`'s vocabulary
already are (see the configurator's CLAUDE.md "Firmware coupling").

**NimBLE's `BLE_UUID128_INIT` takes its 16 bytes in reverse order of the
textual form.** Getting this wrong produces a service that registers cleanly,
advertises cleanly, and is simply never found by the app. The implementation
must write the bytes out explicitly and verify with a scan before building
anything on top.

## 2. Firmware: GATT service registration

All new NimBLE glue lives in `Sources/components/ble_helper.c`. The
`ble_gatt_svc_def` table is a static array of nested structs with function
pointers and bitfields — the same reason the advertising fields stayed in C
rather than moving to Swift (see that file's header comment). No logic moves
into C: the callback delegates immediately to existing Swift.

- A single primary service with two characteristics: **packet**
  (`BLE_GATT_CHR_F_WRITE`, with `access_cb`) and **response**
  (`BLE_GATT_CHR_F_NOTIFY`, with its `val_handle` captured at registration
  into a file-static).
- Registration via `ble_gatts_count_cfg` + `ble_gatts_add_svcs` during
  NimBLE init, before the host starts, alongside the services `esp_hidd`
  already brings up.
- The connection handle is captured from the GAP connect event so
  `ble_gatts_notify_custom` has somewhere to send responses.

The write callback:

1. Flatten the `os_mbuf` with `ble_hs_mbuf_to_flat` into a 32-byte buffer.
2. Reject any length that is not exactly 32 (`BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN`).
3. Call `smk_keymap_dispatch_packet(packet, response)` — the existing
   `@_cdecl` Swift entry point in `Sources/SMKCore/KeymapProtocol.swift`,
   unchanged.
4. Notify the 32-byte response on the response characteristic's value handle.

Dispatch runs inline on the NimBLE host task. COMMIT performs a blocking NVS
write and therefore briefly stalls the stack — this is exactly what the
current `ESP_HIDD_OUTPUT_EVENT` path does, so it is parity rather than a new
problem. Worth a comment; not worth a worker task.

## 3. Firmware: advertising layout

The advertisement has 31 bytes and currently carries flags (3) + appearance
(4) + name `"SMK Keyboard"` (14) = 21. A 128-bit UUID costs 18 more, which
does not fit. So:

- **Primary advertisement:** flags + appearance + `uuids128` (25 bytes).
- **Scan response:** the device name, via `ble_gap_adv_rsp_set_fields`.

Putting the service UUID in the primary packet means the app's
`scanForPeripherals(withServices:)` filter matches without depending on how
Core Bluetooth merges scan-response data. `start_advertising()` keeps its
existing call sites on the START and DISCONNECT events.

## 4. Firmware: removing Report ID 2

Report ID 2 disappears from `hid_report_map` in `ble_helper.c`, and with it
the keymap branch of `ble_hidd_event_callback` in
`Sources/smk/BleHelper.swift:148-168` — including the
`esp_hidd_dev_input_set(dev, 0, 2, ...)` response write. That file ends up
handling only real HID traffic. The report map shrinks, so any hard-coded
descriptor length beside it must be re-derived rather than left stale.

## 5. App: `BLETransport` rewrite

Deletions first: `hidServiceUUID`, `reportCharacteristicUUID`,
`reportReferenceDescriptorUUID`, `targetReportID`, the report-type constants,
and the descriptor walk that existed only to find one characteristic among a
HID service's many. What replaces it is smaller.

**Discovery has two paths, and the fast one is the common case.** A keyboard
that is bonded to the Mac and in use is *connected to the system and not
advertising*, so a scan would find nothing exactly when the keyboard is
working normally:

1. `retrieveConnectedPeripherals(withServices: [uploadServiceUUID])` — no
   scan, for a board already connected to the Mac. This works only because
   we are matching on a custom service; Core Bluetooth would never report a
   HID match here.
2. Fall back to `scanForPeripherals(withServices: [uploadServiceUUID])` with
   the existing 10s timeout, for an unbonded or idle board.

**`connect()` must not resolve until notifications are live.** Today it
resolves once the write characteristic is found. It must now also await
`didUpdateNotificationStateFor` after `setNotifyValue(true)`, because a
packet written before the subscription is active produces a response with
nobody listening.

**`send(_:)` resolves on the notification, not the write ack.** The write
uses `.withResponse`, but `didWriteValueFor` carries no payload and can
arrive either side of the notification; only `didUpdateValueFor
characteristic` has the ACK/NAK byte. A 5s per-packet response timeout fails
the upload instead of hanging it, which is what the current code does.

`DeviceTransport` and `KeymapUploadProtocol` are untouched.

## 6. App: status and progress

`KeymapUploader` gains a `UploadPhase` enum (`.begin`, `.chunk(index: Int,
of: Int)`, `.commit`) and `upload` takes an optional
`progress: ((UploadPhase) -> Void)?`. It is transport-agnostic, so the USB
path gets progress for free.

`EditorState` gains `bleConnected: Bool` and
`uploadProgress: KeymapUploader.UploadPhase?` (nil when no upload is in
flight), both plain stored properties mutated on the main actor — no
`didSet`, per the `@ObservableObject` rule that class already follows.

`DeviceListColumnView`'s BLE card stops hardcoding `isConnected: false` and
reads `editor.bleConnected`. A **Test Connection** button goes in
`DeviceMainContentView`, beside the existing Send to Device action: it
connects and disconnects without uploading, which is the non-destructive
answer to "is it reachable?". `refreshDeviceStatus()` deliberately does *not* scan in the
background: USB's probe is a cheap open/close, but a BLE scan takes seconds
and polling it would stutter the UI and cost battery. Status changes on
explicit action only — Test Connection, or an upload finishing.

## 7. Error handling

`DeviceTransportError`'s existing cases cover this; the new paths map onto
them deliberately:

- Neither discovery path yields a peripheral → `.noDeviceFound`.
- Service or characteristic missing after discovery → `.transportFailure`
  naming the missing UUID. This is the symptom of a UUID mismatch between
  the two repos and must be legible, not generic.
- Response timeout → `.transportFailure` naming the packet index.
- Status byte `0x01` → `.nak`, as today.
- Disconnection mid-upload fails the in-flight continuation instead of
  leaving it suspended forever.

## 8. Testing

- `smk_keymap_dispatch_packet` is unchanged and already covered by the
  firmware's host unit tests. The new firmware surface is C glue: the
  length check and the notify path, which only hardware exercises.
- App side: `KeymapUploadProtocol`'s framing tests already exist; add
  coverage for the progress callback sequence against the fake
  `DeviceTransport` the `KeymapUploader` suite already has.
- Neither test suite can prove GATT plumbing. The acceptance test is the
  hardware round trip: flash, Test Connection, upload a keymap with a
  distinctive remap, confirm it takes effect and survives a power cycle.
- The scan and GATT-enumeration probes built during investigation are the
  fastest way to verify the service and advertisement before touching the
  app (`blescan` / `blediscover`, Core Bluetooth, read-only).

## 9. Phase 2 (separate plan): encryption and reliable reconnect

Phase 1 leaves the upload characteristic writable by any connected client —
matching the board's current posture, where every service is reachable with
no pairing at all. **Known limitation: anyone in radio range can rewrite the
keymap.** Phase 2 closes that and, in the same pass, addresses the goal that
the keyboard should reconnect to a MacBook without being re-added.

Investigation on 2026-08-15 found the bonding groundwork already correct:
`ble_helper.c:165-169` sets `sm_bonding = 1`, `sm_sc = 1`,
`sm_io_cap = NO_IO`, and distributes `ENC | ID` (the IRK exchange is what
lets a host re-identify the keyboard); `sdkconfig` has
`CONFIG_BT_NIMBLE_NVS_PERSIST=y`, `SMP_ID_RESET` unset, and a stable public
address. Phase 2 therefore is not a rebuild, it is:

- `BLE_GATT_CHR_F_WRITE_ENC` on the packet characteristic, plus handling
  bonded peripherals in `BLETransport`.
- **`CONFIG_BT_NIMBLE_MAX_BONDS=1` is the setting that would defeat the
  goal**: one bond slot means pairing a second Mac evicts the first, which
  reproduces the re-add ritual exactly. Raise it (3–5).
- Confirm the factory-reset-on-boot path in `Sources/smk/Main.swift` clears
  the keymap without clearing BLE bonds, and note that `idf.py flash`
  preserves NVS while `erase_flash` does not.
- Acceptance test: pair, reboot the board, close and reopen the lid, and
  confirm the keyboard returns with no intervention; then repeat across two
  Macs.
