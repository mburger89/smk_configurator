# Macro creation — design

Date: 2026-08-20
Design source: `design_handoff_macro_creation/` (3a step editor, 3b flow view),
plus `docs/Macro_view_ideas.pdf` (macro library screen, earlier exploration).

## Problem

The configurator can bind a key to a keystroke, a modifier, a layer switch, or a
connection toggle — one action per key. There is no way to bind a *sequence*:
type a string, wait, send a chord, hold a layer while it runs. Every keyboard in
this class has macros; SMK has none, in either repo.

The design handoff draws a finished macro subsystem. Most of it does not exist
yet on either side:

| Drawn as finished | Actual state |
|---|---|
| `macro:5` bound to a key, "Save & flash" | firmware `KeyAction` has no macro case; no macro store; no player |
| "148 of 384 bytes · slot 3" | no firmware byte budget exists to measure against |
| "Record from board" | no device→host event channel in either transport |
| Conditions, "Simulate", flow view (3b) | needs a macOS helper daemon that does not exist |
| "Back to library" | library screen is in the PDF, not in the handoff |

That is five independent projects. This document settles the contracts that bind
all five, then specifies the first one in full. Each remaining sub-project gets
its own spec.

## Decisions taken

Three forks were settled before design, and they shape everything below.

1. **Execution is board-only.** Macros compile to bytecode and play back in
   firmware, so they work on any host — another computer, a phone over BLE, a
   BIOS screen. The macOS helper is deferred. Conditions are therefore
   unimplementable for now, and 3b ships as a graph rendering of linear steps.
2. **Macros ride inside `keymap.json`,** in a new top-level array, and
   `SMK_KEYMAP_MAX_LEN` rises from its single 4085 to a per-port value. This
   reuses the whole existing upload path unchanged and keeps one document as one
   source of truth.
3. **The library takes the whole workspace,** swapping to the editor when a
   macro is opened — the layout the handoff draws. Macros mode is the only rail
   mode with sub-states.

A fourth came out of review: the editor's primary button is **Save**, not "Save &
flash". Saving publishes the macro as a placeable key; flashing stays where it
already lives.

## Cross-cutting contracts

These bind all five sub-projects and are expensive to change later.

### C1 — Schema

Macros are a new top-level array in `keymap.json`, parsed by the cJSON the
firmware already uses:

```json
"macros": [
  { "id": 5, "name": "Build & deploy", "steps": [
      { "t": "key",   "k": "key:b", "mods": ["leftGUI", "leftShift"], "hold": 40 },
      { "t": "delay", "ms": 400 },
      { "t": "text",  "s": "deploy --env staging", "cpm": 12 },
      { "t": "layer", "op": "mo", "n": 1 },
      { "t": "rpt",   "count": 2, "steps": [] } ] } ]
```

Keystroke steps reuse the existing `key:` / `mod:` strings verbatim. The
generated `KeyName` vocabulary and its codegen (`~/esp/SMK/keycodes.json` →
`KeyCodesGenerated.swift`) therefore serve macros too; there is no second
vocabulary to keep in sync, and no second generator.

Binding is a new action token `macro:5`, added to `ActionToken` and to the
firmware's `KeyAction.fromCString` in lockstep — the grammar stays hand-written
on both sides, as it already is for `key:` / `mod:` / `mo:` / `tg:`.

Unknown step types round-trip through a `.raw` case rather than being dropped,
matching the lossless principle `KeymapDocument` and `ActionToken` already
follow. A macro authored by a newer build survives an older build's save.

### C2 — Capacity is discovered, never hardcoded

The supported ports range from SAMD21 (tiny flash) to ESP32-C6 and RP2040. A
fixed "8 KB / 32 slots" would be wrong at both ends, so capacity is reported by
the board.

A new `CAPS` command on the existing transport returns
`{ macroBytes, macroSlots, keymapMaxLen }`. The editor behaves as follows:

| Situation | Behaviour |
|---|---|
| Device connected | Meter is exact, from the board's own numbers |
| Disconnected, seen before | Last-known caps, persisted per device |
| Never seen | The floor profile — one editor-side constant describing the smallest supported board, superseded by any real `CAPS` response; meter labelled *estimated* |
| Board reports 0 macro bytes | Authoring and export still work; flashing disabled, with the reason shown |
| Macro exceeds caps | Warns in the library row and status bar; blocks flashing only — never editing or saving to disk |

A small-flash board degrades to author-and-export. A large-flash board simply
shows more headroom. No editor constant needs bumping when a new port lands.

### C3 — The byte meter is real

The editor compiles steps using the same sizing rules the firmware uses, so
"148 of 384 bytes" is computed rather than decorative. One shared sizing table,
pinned by a test on both sides — the discipline `KeyVocabularyTests` already
applies to the key vocabulary.

### C4 — Deferred parts degrade honestly

Condition nodes can be authored and saved, but are rejected at flash time with a
clear message until the helper exists. "Record from board" renders but is
disabled with its reason. "Test run" walks the steps and writes a real timing
trace into the inspector log, but emits no keystrokes — synthesising them into
the host is helper work.

Nothing in the UI claims a capability the build does not have.

## Sub-project 1 — Macro model, macros rail mode, step editor (3a)

### Model

A new `Model/Macro.swift`:

- `MacroDefinition` — `id` (the slot), `name`, `steps`
- `MacroStep` — `.keystroke(mods, key, holdMs)`, `.text(string, delivery, msPerChar)`,
  `.delay(ms)`, `.layer(op, n)`, `.repeatBlock(count, steps)`, `.raw(JSONValue)`
- `compiledSize` on both, implementing C3

`repeatBlock` does **not** nest: its `steps` may not themselves contain a
`repeatBlock`. One level keeps the firmware's player a single loop counter
rather than a stack, which matters on the smallest ports. The editor enforces
this by refusing the Repeat block palette type while editing inside one, and a
nested block loaded from a file is preserved as `.raw` rather than executed.

`ActionToken` gains `.macro(Int)` with canonical string `macro:5`. One wrinkle:
every other token's `displayLabel` is self-sufficient, but a macro keycap should
read "Build & deploy", which needs a document lookup. `displayLabel` returns
`M5`, and `KeyCapView` takes an optional name resolver. This is the only place a
token's label is not standalone.

### State

`RailMode` gains a fifth case, `macros`. `EditorState` gains
`MacroWorkspace { case library, editor(id: Int) }` plus `selectedStepIndex`.
Macros mode is the only rail mode with sub-states, so this stays one small enum
rather than a general mechanism.

### Save publishes a placeable key

The editor's primary button is **Save**. Saving writes into `document.macros`
and marks the document dirty, which the existing status-bar text already
reports. A new **MACROS** section then appears in the KEY-mode palette drawer,
one chip per saved macro carrying `.macro(id)`, dropped onto a key like any
other token. Flashing stays exactly where it lives today — `sendToDevice()`,
one upload carrying matrix, layers, and macros together. Nothing new on the
device path.

There is a constraint hiding in that. `PaletteDrawerView.keySections` is
`static`, and its height math feeds `ContentView.minWindowHeight`. A macros
section whose row count grew with the document would make the window's minimum
height depend on how many macros the user owns. **The MACROS section is
therefore fixed at one horizontally-scrolling row regardless of count**, so the
static height math stays static.

### Interaction: no drag, no keyboard shortcuts

SwiftCrossUI's entire gesture vocabulary is `onTapGesture`, `onHover`,
`onChange`, `onSubmit`, `onOpenURL`. There is no drag support of any kind, and
no `keyboardShortcut` — `CommandMenu` items carry no key equivalents either.
Four things the handoff specifies are not buildable, and are substituted:

| Design | Substitute |
|---|---|
| 3-line drag handle, 11px column | Same column and footprint; ▲▼ reorder buttons revealed on hover/selection |
| ⌫ to delete | ✕ at the row's trailing edge on hover, plus Delete in the inspector's Step tab |
| Drag a palette row onto a position | Tap a row to select, then tap a palette type — inserts *after* the selection |
| Dashed drop zone + ⌘⏎ | The same dashed card, now a tappable **"+ Add step"** button |

Two strings change accordingly, because shipping them as drawn would be UI text
that lies:

- "Drag to reorder · ⌫ to delete" → **"Select a step to reorder or delete"**
- "Drop a step type here, or press ⌘⏎ to append" → **"Add a step"**

`Slider`, `TextEditor`, `Picker`, and `ToggleSwitch` all exist natively, so the
inspector is unaffected.

### Views

Split rather than one file, since existing views sit at 100–300 lines each:

- `MacroLibraryView.swift` — the full-body table, re-skinned from the PDF onto
  the rail shell: MACRO / TRIGGER / KIND / STEPS / LAYER / EDITED, search,
  "Record new", "New macro", capacity summary, unflashed-changes indicator
- `MacroEditorViews.swift` — the 212px step palette and the canvas header
- `MacroStepRowView.swift` — one row, the fiddliest piece
- `MacroInspectorView.swift` — the Step / Macro / Timing tabs

`ContentView`'s three column properties each gain a `.macros` case switching on
`MacroWorkspace`.

Every new tap target must express its selected state as *values*, not branches —
`background: isSelected ? chrome.accentWash : chrome.column`,
`border: isSelected ? chrome.accent : .white.opacity(0.05)` — because
`TapTarget.body` cannot contain an `if`. That constraint is documented at
`UIStyle.swift:98`, and violating it is what once squashed the icon rail's 40×40
tiles to 40×30. One open detail: the dashed hairline on the add-step card needs
`StrokeStyle` dash support, or it falls back to a solid low-opacity border.

No new colours. Everything comes from `Chrome`; the badge colours reuse the
keycap palette already in the keymap view.

### Rail icon

`.macros` is added to `AppIcon`'s enum with fallback label `"MAC"`, and
`Scripts/generate-icons.sh` gains a `wand.and.stars` render for macOS, Fluent
`ic_fluent_wand_24_regular.svg` for Windows, and Adwaita
`applications-utilities-symbolic.svg` for Linux. The PNG shipped in the handoff
is a placeholder and is not committed.

### Testing

- **Codec** — `MacroDefinition` ⇄ JSON round-trip, including that an unknown
  step type survives via `.raw`
- **Document stability** — a `keymap.json` without a macros key must not gain
  `"macros": []` on save; the reference file must not churn just from being
  opened
- **Token** — `macro:5` parse and canonical round-trip; `macro:abc` degrades to
  `.raw`
- **Compiled size** — the sizing table pinned against the firmware's rules,
  cross-repo
- **Capacity** — all five meter states from C2
- **Reorder** — move up/down at the list boundaries; deleting adjusts the
  selection sensibly

## Remaining sub-projects

Each gets its own spec before implementation.

2. **Macro library polish** — collections, search, per-macro enable/disable,
   duplicate, export. The table itself lands in sub-project 1 because the editor
   needs somewhere to return to.
3. **Firmware macro support** (`~/esp/SMK`) — `macro:N` in `KeyAction`, macro
   parsing, the bytecode player, a per-port capacity profile, the `CAPS`
   command, a char→HID table for text steps, and the `SMK_KEYMAP_MAX_LEN` /
   partition change. This is what makes C3's byte figures load-bearing.
4. **Record from board** — a device→host event channel over both transports,
   plus capture session state and gap measurement in the editor.
5. **Flow view (3b)** — the node graph over linear steps. Note that SwiftCrossUI's
   missing drag support also rules out "drag from a port to add a node", so this
   sub-project needs its own interaction rethink. Condition nodes stay inert
   until the helper lands.

**Helper daemon** — out of scope for this program by decision, and a prerequisite
for conditions ever executing.

## Open questions

- Per-port capacity profiles: the concrete numbers per board are decided in
  sub-project 3, alongside the partition change.
- Text steps assume the host's keyboard layout matches the usages sent. This is
  the standard limitation for board-side text macros and is documented rather
  than solved.
