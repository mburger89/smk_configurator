# Layer add/remove controls — design

## Problem

The Layers section of the KEY-mode list column (`KeyListColumnView` in
`Sources/SMKConfigurator/Views/KeyModeViews.swift`) lets you select an
existing layer but has no way to add a new one or remove one you no longer
want. `EditorState.addLayer()` / `EditorState.removeCurrentLayer()` already
exist but are unused dead code — no UI calls them, and there's no cap on
layer count.

## Design overview

**Add layer** — a small "+" chip appended to the trailing edge of the
"LAYERS" section header row, styled like the existing `+`/`–` stepper chips
in `PaletteDrawerView.swift` (20×20 `TapTarget`, `chrome.chipBackground`,
`cornerRadius: 4`). Tapping it calls `editor.addLayer()` and selects the new
layer, matching current behavior. The chip is disabled (dimmed, no-op) once
`document.layers.count == 10` — a new cap, since none exists today.

**Remove layer** — each layer row already renders via `layerRow(index)` in
`KeyListColumnView`. It becomes a small stateful view (`@State private var
isHovering`) using SwiftCrossUI's `.onHover(perform:)`. When hovering AND
`index != 0` (layer 0 is "Base" and is never deletable — deleting it would
remove the layer the firmware treats as the always-present default), a
trailing trash glyph (`Text("🗑")` or similar text glyph — codebase has no
SF Symbols, only text/emoji glyphs per `Views/AppIcon.swift`'s doc comment)
appears, colored with `chrome.dangerText` to match the existing destructive
styling convention (`InspectorButton(isDestructive:)`).

Tapping the trash glyph calls `presentAlert("Delete Layer \(index)?")` with
Delete/Cancel actions — SwiftCrossUI's built-in alert API
(`PresentAlertAction`, already used for `editor.loadError` in
`ContentView.swift`). On confirming Delete, calls a new
`EditorState.removeLayer(at index: Int)`.

## Model changes (`EditorState.swift`)

- `addLayer()` — add a guard: no-op if `document.layers.count >= 10`.
- New `removeLayer(at index: Int)` — mirrors `removeCurrentLayer()` but
  takes an explicit index: guarded to require `document.layers.count > 1`
  and `index != 0`; removes at `index`; clamps `currentLayer` if it was
  pointing at or past the removed index; sets `isDirty = true`.
- `removeCurrentLayer()` stays as-is (still unused, harmless to leave).

## UI changes (`KeyModeViews.swift`)

- "LAYERS" section header row becomes an `HStack` with `SectionHeader(title:
  "Layers")` + `Spacer()` + the new add-layer chip, replacing the bare
  `SectionHeader(title: "Layers")` call at line 31.
- `layerRow(_:)` (currently a plain function returning `some View`) becomes
  a small nested `View` struct (needs `@State` for hover), taking `index`,
  `isSelected`, and closures/environment it needs (`editor` via
  `@Environment`, same as the parent). Trailing `HStack` gets the
  conditionally-shown trash glyph before the existing `Spacer()`.

## Testing notes

No test target covers UI views in this SwiftCrossUI app (build/run only,
per CLAUDE.md — macOS is the only locally runnable platform). Verify by
running `swift run SMKConfigurator`, adding layers to 10 (button disables),
hovering non-Base layer rows (trash appears), deleting via the confirm
alert, and confirming Base (layer 0) never shows a trash icon even on
hover.
