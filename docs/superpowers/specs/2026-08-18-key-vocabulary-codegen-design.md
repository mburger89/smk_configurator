# Key Vocabulary Codegen — Full HID Keyboard-Page Coverage

Date: 2026-08-18
Status: Approved, pending implementation plan
Scope: spans two repos — `~/esp/smk_configurator` (this one) and `~/esp/SMK` (firmware)

## Problem

The configurator's key palette is missing keys. Investigation showed the gap is
not editor-only: `KeyName` in `Sources/SMKConfigurator/Model/ActionToken.swift`
already covers *exactly* the vocabulary `KeyCode.fromCString` parses in
`~/esp/SMK/Sources/SMKCore/LayerEngine.swift`, and `PaletteDrawerView` already
renders all of it. Editor and firmware are perfectly in sync — both are
incomplete against the HID keyboard usage table.

Measured against QMK's `data/constants/keycodes/keycodes_0.0.1_basic.hjson`,
**83 keyboard-page usages in the range 0x04–0xA4 are absent from both repos**:

| Range | Keys | Count |
|---|---|---|
| 0x32, 0x64 | `nonUSHash`, `nonUSBackslash` (ISO) | 2 |
| 0x49 | `insert` | 1 |
| 0x53–0x63, 0x67, 0x85, 0x86 | Num Lock + full keypad cluster | 18 |
| 0x66 | `keyboardPower` | 1 |
| 0x68–0x73 | F13–F24 | 12 |
| 0x74–0x7E | Execute, Help, Menu, Select, Stop, Again, Undo, Cut, Copy, Paste, Find | 11 |
| 0x7F–0x81 | keyboard-page Mute / Volume Up / Volume Down | 3 |
| 0x82–0x84 | Locking Caps / Num / Scroll Lock | 3 |
| 0x87–0x8F | International 1–9 | 9 |
| 0x90–0x98 | Language 1–9 | 9 |
| 0x99–0xA4 | AltErase, SysReq, Cancel, Clear, Prior, Return, Separator, Out, Oper, ClearAgain, CrSel, ExSel | 12 |

`insert` is the most conspicuous: the navigation cluster has Home/End/PgUp/PgDn/Delete
but no Insert.

Behind that sits a structural problem. The vocabulary is **hand-mirrored across two
repos** — an 85-line `strcmp` if-chain in the firmware, a parallel `KeyName` enum plus
85 hand-written `displayLabel` cases here. Nothing checks that the two agree. When they
disagree, the failure is silent: the editor writes a token, the firmware's `fromCString`
falls through to `.noKey`, and the key does nothing with no error anywhere. Adding 83
keys doubles that hand-maintained surface and roughly doubles the odds of that bug.

### Deliberately out of scope (Spec 2)

Consumer-page media keys (Play/Pause, Volume, Brightness, browser/app launch) and
Generic Desktop System Control (Power/Sleep/Wake) were originally in scope and have been
split into a follow-up spec. Rationale: the 83 keyboard-page keys need **zero** transport
work — they are `UInt8` values flowing through the existing 8-byte report — whereas media
keys need new report collections plumbed through **11 send-function implementations across
6 MCU ports**:

| Transport | Implementations |
|---|---|
| BLE | `Sources/smk/BleHelper.swift` (ESP32-C6 / `esp_hidd`), `ports/common/BleHidGatt.swift` (BTstack: pico_w, pico2_w, nrf52840, stm32wb), `ports/rp2040/BleHidPicoW.swift` (stub branch), samd21 + stm32f4 C stubs |
| Wired | `ports/{rp2040,samd21,nrf52840,stm32wb,stm32f4}/UsbHid.swift`, `Sources/smk/WiredHidUart.swift` |

One of those is blocked on unverified hardware capability: ESP32-C6's "wired" path is not
USB but a **CH9350 USB-HID bridge chip** over UART with a fixed 12-byte frame whose byte
[2] is hardcoded `ID 0x01 (Keyboard)` (`WiredHidUart.swift:132`). Whether it accepts a
Consumer frame ID is a property of that chip's firmware and needs research before design.

Accordingly **`keycodes.json` ships with only a `keyboard` section in this spec.**
Generating `cons:`/`sys:` tokens now would put palette chips in front of the user that
silently do nothing — exactly the failure mode this work exists to eliminate. Spec 2 adds
those arrays; the generator is written to tolerate absent sections.

Also out of scope: mouse keys, and any change to `SMK_KEYMAP_MAX_LEN`.

## Design overview

Five pieces:

1. **`keycodes.json`** — a manifest in `~/esp/SMK`, single source of truth for the entire
   key vocabulary (existing keys included, not just new ones).
2. **`generate_keycodes.sh`** — a generator writing Swift into *both* repos, modeled
   directly on the existing `generate_ble_uuids.sh`.
3. **Firmware**: generated `KeyCode` enum + table-driven `fromCString`; BLE report-map
   usage-max widening; the duplicated report map hoisted into `SMKCore`.
4. **Configurator**: generated `KeyName` + labels + palette groups; `PaletteDrawerView`
   grows 8 → 12 sections with its height math made data-driven.
5. **Tests** pinning cross-repo agreement — the mechanical check that does not exist today.

### Why codegen rather than extending the `strcmp` chain

This repo already pays exactly this cost for a cross-repo constant: `ble_upload_uuids.json`
→ `generate_ble_uuids.sh` → `Sources/components/smk_ble_uuids.h` **and**
`Sources/SMKConfigurator/Device/BLEUploadUUIDs.swift`, pinned by `BLEUploadUUIDsTests`.
The precedent, the failure mode, and the fix are the same shape. At 168 vocabulary
entries (85 existing + 83 new), hand-mirroring stops being sustainable — and Spec 2 adds
another ~28 on top.

## 1. `keycodes.json` (new, `~/esp/SMK/keycodes.json`)

```json
{
  "keyboard": [
    { "name": "a",              "usage": 4,   "label": "A",    "group": "letters" },
    { "name": "insert",         "usage": 73,  "label": "Ins",  "group": "navigation" },
    { "name": "keypadAsterisk", "usage": 85,  "label": "*",    "group": "keypad" },
    { "name": "international1", "usage": 135, "label": "INT1", "group": "international" }
  ]
}
```

- `name` — the token string after `key:`. **camelCase full words**, consistent with the
  existing `leftBracket` / `printScreen` style. Chosen over QMK-style abbreviations for
  consistency and self-documenting hand-edited keymaps, accepting the payload cost (see
  Risks).
- `usage` — HID usage ID, decimal.
- `label` / `group` — consumed by the *editor* only. Generated rather than hand-written
  because 83 hand-maintained display labels and their section assignments are the same
  drift problem one layer up.

Groups (10, covering `KeyName` only): `letters`, `digits`, `editing`, `functionKeys`,
`keypad`, `navigation`, `editingCommands`, `system`, `international`, `legacy`. The
palette's other two sections — Modifiers and Layers & Special — are built from
`ModifierName` and `ActionToken` cases respectively and are not manifest-driven, which is
why 10 groups yield 12 sections in §4.2.

`noKey` (0x00) and `transparent` (0xFF) are **not** in the manifest — they are grammar
sentinels, not keys, and `transparent` is already handled a level up at `KeyAction`. The
generator injects them into the firmware enum directly.

## 2. `generate_keycodes.sh` (new, `~/esp/SMK/generate_keycodes.sh`)

Same CLI shape and structure as `generate_ble_uuids.sh` — `set -euo pipefail`,
`cd "$(dirname "$0")"`, `CONFIGURATOR="${1:-../smk_configurator}"`, body as
`python3 - "$CONFIGURATOR" <<'PY'`. Emits the same "Generated by … Do not edit by hand"
header both existing generated files carry.

Outputs:

| File | Repo | Contents |
|---|---|---|
| `Sources/SMKCore/KeyCodesGenerated.swift` | SMK | `KeyCode` enum, `rawValue` switch, `table`, `fromCString` |
| `Sources/SMKConfigurator/Model/KeyCodesGenerated.swift` | configurator | `KeyName` enum, `displayLabel`, group arrays |

Determinism is required: regenerating from an unchanged manifest must produce
byte-identical output (manifest order preserved; no dict iteration, no timestamps).

## 3. Firmware changes (`~/esp/SMK`)

### 3.1 Generated `KeyCode`

`Sources/SMKCore/KeyCodesGenerated.swift` replaces the hand-written `KeyCode` enum and its
85-line `strcmp` chain in `LayerEngine.swift`:

```swift
enum KeyCode: UInt8 { case noKey, a, b, /* … */ exsel, transparent }

extension KeyCode {
    static let table: [(StaticString, KeyCode)] = [("a", .a), /* … */]
    static func fromCString(_ s: UnsafePointer<Int8>) -> KeyCode { /* table walk */ }
    var rawValue: UInt8 { /* generated switch */ }
}
```

Note the structure being preserved: the existing enum declares `: UInt8` (so Swift
synthesizes ordinal raw values) *and* an explicit computed `var rawValue: UInt8` that
overrides them with real HID usage IDs. The generator must reproduce that exact shape —
emitting `case a = 4` style explicit raw values instead would be a silently different
type, since `LayerEngine` and `HIDReport.addKey` depend on `rawValue` being the HID usage.

The table walk is the same O(n) `strcmp` sequence the if-chain already was — no
performance change, ~170 lines of boilerplate replaced by ~6 lines of logic plus data.
At ~170 entries × 300 cells this remains microseconds at boot.

`KeyAction.fromCString`'s prefix dispatch (`key:` / `mod:` / `mo:` / `tg:` / `none` /
`trans` / `toggle_conn`) stays hand-written and **unchanged** — only the vocabulary is
generated, not the grammar. `Modifier` is likewise untouched (8 stable cases).

### 3.2 BLE report-map widening

Both BLE report maps declare the keycode array as:

```
0x95, 0x06, 0x75, 0x08, 0x15, 0x00, 0x25, 0x65, 0x05, 0x07, 0x19, 0x00, 0x29, 0x65, 0x81, 0x00
                                    ^^^^^^^^^^                        ^^^^^^^^^^
                                    Logical Max 101                   Usage Max 101
```

Every new key above `application` (0x65) — `keypadEqual` 0x67, F13–F24, Undo/Cut/Copy/Paste,
INT/LANG, the 0x99–0xA4 block — falls **outside the declared range** and may be dropped by
the host. Fix, in both maps:

- `0x25, 0x65` → `0x26, 0xFF, 0x00` (Logical Maximum 255, two-byte)
- `0x29, 0x65` → `0x2A, 0xFF, 0x00` (Usage Maximum 255, two-byte)

Each map grows by 2 bytes. `hidReportMapBytes` uses `.count`, so ESP32-C6 needs no length
edit; `BleHidGatt.swift`'s equivalent must be checked for a hardcoded length.

**USB needs no descriptor change at all.** `TUD_HID_REPORT_DESC_KEYBOARD()` already
declares `HID_USAGE_MIN(0)` / `HID_USAGE_MAX_N(255,2)` and `HID_LOGICAL_MAX_N(255,2)`
(verified in `~/pico-sdk/lib/tinyusb/src/class/hid/hid_device.h:200-208`), so all 83 keys
work over USB the moment the firmware knows their names.

### 3.3 Hoist the shared report map into `SMKCore`

`Sources/smk/BleHelper.swift:87-90` and `ports/common/BleHidGatt.swift:143-146` hold
**byte-identical** copies of the report map, and §3.2 changes both identically — the exact
drift risk this spec is about, sitting in a file already being edited. Move the constant to
`Sources/SMKCore` (the cross-platform module both `smk` and `ports/common` already depend
on) as `hidKeyboardReportMap`, and have both sites reference it.

Targeted, not speculative: it is the one cross-cutting constant the codegen cannot cover.

### 3.4 Explicitly untouched

`HIDReport`, `processKeyEvents`, all 11 send functions, both USB descriptor files. The 83
new keycodes are `UInt8` values flowing through `HIDReport.addKey` identically to existing
ones. This is asserted by tests rather than assumed (§5).

## 4. Configurator changes

### 4.1 Generated `KeyName`

`Sources/SMKConfigurator/Model/KeyCodesGenerated.swift` carries `KeyName` (all cases),
`displayLabel`, and the group arrays the palette iterates.

`ActionToken.swift` keeps `ActionToken`, `ModifierName`, and all parse/`canonicalString`
logic hand-written; it loses only `KeyName`. `ActionToken.raw(String)` is unchanged, so a
keymap written by a *newer* firmware still round-trips losslessly through this editor.

### 4.2 `PaletteDrawerView`: 8 → 12 sections

Folded into existing sections: `insert` → Navigation; `nonUSHash`/`nonUSBackslash` →
Editing & Punctuation; F13–F24 → Function Keys (now 2 rows); keyboard-page
Mute/Vol±/`keyboardPower`/Locking locks → System.

Four new sections: **Keypad** (18), **Editing Commands** (11), **International** (18, 2
rows), **Legacy** (12).

The palette stays **untabbed** — `PaletteDrawerView`'s own doc comment records that
sections are "shown simultaneously (not tabbed)" as deliberate design. The existing
chunk-into-N-rows + horizontal `ScrollView` primitive is kept as-is; no wrapping layout.

### 4.3 Drawer height math (the substantive UI work)

`contentHeight` today hardcodes "6 one-row sections + Letters at 2 rows + Layers &
Special". Twelve sections would compute a `maxHeight` near 900pt — taller than the
1366×768 laptop case `maxHeight`'s comment explicitly exists to protect. Its own comment
already records this desyncing once before, when Function Keys/System were added and
"Layers & Special" was silently clipped out of view.

Two changes:

1. Derive both `body` and the height calculation from **one `sections` array** of
   `(title, tokens, rows)`, so adding a section can never again desync the height.
2. **Cap `maxHeight`** at approximately today's value and order sections by usage
   frequency — Letters, Numbers, Editing & Punctuation, Function Keys, Navigation,
   Modifiers, Keypad, Editing Commands, System, International, Legacy, Layers & Special —
   so common sections sit above the fold and the rare tail scrolls vertically.

`minHeight`, the `.layoutPriority(1)` contract with the board, and `ContentView`'s window
`minHeight` are unchanged.

### 4.4 Coupling bookkeeping

- Bump `firmwareVersionLabel` in `EditorState.swift`.
- `CLAUDE.md`: add `keycodes.json` / `generate_keycodes.sh` to both the "Firmware coupling"
  list and the generated-files note; record that `KeyCodesGenerated.swift` is generated and
  must not be hand-edited.
- **Fix a stale `CLAUDE.md` claim** found during design: it describes `BLETransport` as
  matching "ESP32-C6 builds' HID Report ID 2". `BleHelper.swift:80` records that the
  vendor Report ID 2 channel was removed and upload moved to the custom GATT service
  (macOS hides the HID service from Core Bluetooth entirely). Report ID 2 is now free.

## 5. Testing

Host-testable via `swift test --build-system native` here, and via the `SMKCore` host
surface in the firmware repo:

- **Generator determinism** — regenerating from an unchanged manifest yields byte-identical
  files.
- **Cross-repo agreement** — every `KeyName.allCases` raw string appears in `keycodes.json`
  with a matching usage. This is the mechanical check that does not exist today; modeled on
  `BLEUploadUUIDsTests`.
- **Usage-value pinning** — boundary values asserted against the QMK table: `insert` 0x49,
  `keypadEqual` 0x67, `f24` 0x73, `exsel` 0xA4. A manifest typo must not silently ship a
  wrong keycode.
- **`ActionToken` round-trip** — `parse(canonicalString) == token` across `KeyName.allCases`.
- **Palette coverage** — every `KeyName` case appears in exactly one palette group (no key
  added to the manifest can go unreachable in the UI).
- **BLE report map** — assert the widened bytes, and that both call sites reference the
  single `SMKCore` constant.
- **Firmware `fromCString`** — returns the correct `KeyCode` for every manifest entry and
  `.noKey` for unknown input.

**Not verifiable here, and stated rather than glossed:** real HID behavior against a live
host, and the widened BLE map against a live central. macOS is the only runnable platform
from a dev machine; Windows/Linux are compile-only in CI with no test step.

## Risks

- **Payload budget.** camelCase full words cost bytes against `SMK_KEYMAP_MAX_LEN` (4085).
  Upload is already compact-encoded and layers-only (`encodeLayersJSON`), and the reference
  keymap is 120 cells / 1575 bytes pretty-printed. A 5-layer 60-key map with long tokens
  lands roughly 3.6–4.0KB — inside the cap but without much headroom. Raising the cap means
  a flash frame larger than RP2040's 4KB erase granularity, which is deliberately out of
  scope. Mitigation: none needed now; flagged so a future dense-map report is diagnosed
  quickly.
- **Two-repo commit discipline.** Like `generate_ble_uuids.sh`, regenerating requires
  committing outputs in both repos. The cross-repo agreement test catches a missed
  configurator-side commit; nothing catches a missed firmware-side one. Called out in
  `CLAUDE.md`.
- **Deleting the hand-written `KeyCode`** is the largest single firmware edit here. The
  generated enum must preserve every existing case name and `rawValue` exactly, or existing
  keymaps silently change meaning. Covered by pinning tests over the full manifest, not just
  new entries.
- **`KeyCode`'s synthesized `init?(rawValue:)` is inconsistent and must stay unused.**
  Because the enum declares `: UInt8` with no explicit case values but overrides
  `rawValue`, Swift's synthesized `init?(rawValue:)` maps from *ordinals*, not HID usages —
  `KeyCode(rawValue: 0x04)` would not return `.a`. Verified during design that no call site
  uses it. The generator preserves this shape (§3.1); if a future change needs
  usage → `KeyCode`, it must be a generated lookup, not the synthesized initializer.
