# Macro library — design

Date: 2026-08-22
Sub-project 2 of `2026-08-20-macro-creation-design.md`.
Depends on sub-project 1 (the library table and step editor) and the binary
keymap format, both of which are complete and pending merge.

## Problem

The macro library is a flat table with two actions: open and delete. Once a
user has more than a handful of macros there is no way to find one, no way to
group them, no way to turn one off without losing it, no way to start from an
existing one, and no way to move a macro between machines or share it.

## Scope note

Written and scoped after a YAGNI objection was raised and overruled. The
objection was that with zero macros in existence, search and collections
solve a problem that does not yet exist, and export precedes the usage that
should inform its format. The counter-position — that the library should be
complete before it is used in anger — is the one being built. Recorded so the
reasoning is visible if any of it turns out to be unused.

## Decisions taken

**Collections live in `keymap.json`, not an editor-side store.** This is
forced rather than chosen: `nextMacroID` returns the lowest free slot, so
deleting macro 0 and creating another gives the new macro id 0. Any side
store keyed by id would silently re-attribute the deleted macro's collection
to its replacement. `MacroDefinition` already preserves unknown per-macro
fields, so a `collection` string rides in the document and the firmware
ignores it.

**A disabled macro compiles its bound keys as `none`.** The macro is omitted
from the payload, and any cell holding `macro:<id>` for it compiles as a dead
key. The binding stays in `keymap.json`, so re-enabling restores the key with
no re-binding.

Rejected: refusing to compile, which turns "I am over capacity, switch this
off and flash" into a hunt for bindings — fighting the main reason to disable
something. Also rejected: leaving the binding and letting the board find an
absent slot, which would require the firmware's decoder to tolerate dangling
references, on the other side of a contract just frozen and flashed.

The silent-dead-key risk is mitigated in the library, not the compiler: a row
for a disabled-but-bound macro warns and names the key, which
`MacroLibraryRow` already computes.

**Export is per-macro and round-trippable.** One macro per `.json` file,
importable back into the library. Export without import produces artifacts
nothing can load; a whole-library file cannot share a single macro and
replaces rather than merges on the way back in.

## Design

### 1. Model

`MacroDefinition` gains two fields:

- `enabled: Bool` — defaults `true`. Absent in existing files, so decoding
  must treat missing as enabled or every current macro silently switches off.
- `collection: String?` — nil meaning ungrouped.

Both are ordinary `Codable` members, so they round-trip. The recently added
unknown-field preservation is unaffected.

### 2. Compiler and capacity

`compileKeymap` skips disabled macros entirely and rewrites any cell bound to
one as `none`. `macroCount` in the header reflects only enabled macros, and
step counts follow.

`MacroBudget` counts only enabled macros, so disabling frees real bytes —
which is the point, given macros and layers share one budget.

Both are behavioural changes to a format pinned across two repos. The
firmware never sees a disabled macro, so `BinaryFormatAgreementTests` is
unaffected — but the compiler's own tests must pin that a disabled macro
contributes zero bytes and that its bound cells become `none`.

### 3. Library table

- **Search** filters rows by name and by step content, case-insensitive. A
  field in the header, not a separate mode.
- **Collection** becomes a column and a filter. Assigning is inline on the
  row; the set of collections is derived from what macros actually use rather
  than maintained separately, so an emptied collection disappears on its own.
- **Enable/disable** is a per-row toggle. A disabled row is visually
  de-emphasised and, if bound, warns and names the key.
- **Duplicate** copies a macro into the lowest free slot with a derived name.
  Refuses when no slot is free, rather than silently overwriting.
- **Export/import** are header actions using the app's existing file
  chooser environment values (`chooseFile`, `chooseFileSaveDestination`).

### 4. Import validation

An imported file is untrusted: hand-edited, or from anywhere. It is decoded
through the same `MacroDefinition` path as `keymap.json`, so unknown fields
and mistyped values are preserved rather than coerced — the codec work
already makes this safe.

Import assigns a **fresh slot**, never the id in the file, because that id
almost certainly collides. It refuses when no slot is free, and when the file
does not decode to a macro at all, with a message naming the file.

## Testing

- A macro with no `enabled` field decodes as enabled — the migration case,
  and the one that silently breaks every existing file if wrong
- Disabled macros contribute zero compiled bytes, and their bound cells
  compile as `none`
- `MacroBudget` excludes disabled macros
- Search matches on name and on step content
- Collections derive from macros; emptying one removes it from the filter
- Duplicate takes the lowest free slot; refuses when full
- Export then import round-trips a macro, including unknown fields
- Import assigns a fresh slot rather than the file's, and refuses a
  non-macro file

## Out of scope

- Reordering macros. Slot order is the id order, and ids are a firmware
  resource rather than a display concern.
- Sharing collections between documents. A collection is a string on a macro;
  there is no collection object to share.
- Recording from the board (sub-project 4) and conditional flows
  (sub-project 5), both still blocked on hardware and on the helper.
