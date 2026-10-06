# Porting the SMK configurator from SwiftCrossUI to MetalUI — plan

Date: 2026-10-06. Branch `feat/metalui-port`, from `origin/main` `2e7643e`.
MetalUI pinned at `e54c3f65086b446d42b09bf6f2fdbf802f7ed52a` (its `master`).
Gaps found on the way: [`2026-10-06-metalui-gaps.md`](2026-10-06-metalui-gaps.md).

**The user's decisions** (2026-10-03), binding on every lane: port on this
branch; switch off SwiftCrossUI in one go (no dual build); the chrome palette
becomes MetalUI app palette keys (`ThemeColorKey`, light and dark values);
macOS first — Linux and Windows UI come later, as a separate item; about
fifteen SwiftCrossUI workarounds are **deleted**, not ported (§2.2); every
colour becomes a palette key or a literal `Color`; light/dark icon PNGs pick by
`@Environment(\.colorScheme)`; View ▸ Appearance becomes
`preferredColorScheme`; the device monitor starts and stops with the DEV pane
via `onAppear`/`onDisappear`; a load error becomes an `.alert` via
`onChange(of:)`; keymap/theme/macro import and export use MetalUI's file
dialogs; the menu bar is `App.commands`; the window has a 1440-wide minimum and
a computed height; tooltips are `.help`; dividers are `Divider()`; key and step
choosers over hundreds of options may use `.pickerStyle(.menu)`. `Model/` and
`Device/` move unchanged except where SwiftCrossUI reached into them (§4.3);
Bluetooth stays macOS-only. **`BinaryFormatAgreementTests` and every model test
stay green throughout.**

**Baseline** (before any change, `swift test --build-system native` on
`2e7643e`, macOS, Swift 6.4): `Test run with 225 tests in 24 suites passed`
(XCTest: `Executed 0 tests`). A lane is done only when the same command —
without `--build-system native`, which SwiftCrossUI alone needed — prints at
least 225 tests, all passing, and `swift build` prints no `error:`.

File:line references are to `2e7643e` unless a lane says otherwise; the old
view files are deleted in lane 1, so later lanes read them with
`git show 2e7643e:Sources/SMKConfigurator/Views/<File>.swift`.

---

## 1. Inventory — the parity checklist

Every item below must exist after lane 3 (or be listed under "changes by
decision" with its replacement). The final check ticks this list.

### 1.1 Window, app, menus

- [ ] One window titled **"SMK Keymap Configurator"** (`App.swift:9`).
- [ ] Opens 1440 wide × `idealWindowHeight` (chrome + KEY content with the
      palette at its max, `ContentView.swift:51`, `App.swift:17`); resizable
      down to 1440 × `minWindowHeight` (`ContentView.swift:45`, `:69`).
- [ ] View ▸ Appearance ▸ **Light / Dark / System**, the current one checked,
      persisted (`EditorState.setAppearanceMode`), applied app-wide
      (`App.swift:12`, `:18-32`).
- [ ] Layout: [titlebar 50 → *deleted by decision*] / [icon rail 64 | divider |
      list column 260 (212 in the macro editor, none in the macro library) |
      divider | main (flex) | divider | inspector 300 (248 in the macro editor,
      none in the library)] / divider / status bar 26 (`ContentView.swift:53-69`).
- [ ] DSN/THM draft workspaces seeded from the active design/theme on first
      appearance (`ContentView.swift:70-75`).
- [ ] A non-nil `editor.loadError` shows an alert with its message, then clears
      (`ContentView.swift:76-82`).

### 1.2 File actions (were the titlebar's icon buttons; now the File menu)

- [ ] **New** → `editor.newDocument()` (`TitlebarView.swift:15`).
- [ ] **Open…** → open panel ("Open keymap.json", starts in `~/esp/SMK`) →
      `editor.load(from:)` (`:18-28`).
- [ ] **Save** → `editor.save(to: fileURL)`, or Save As when untitled (`:29-37`).
- [ ] **Save As…** → save panel ("Save keymap.json", default `keymap.json`)
      (`:38-40`, `:80-89`).
- [ ] **Import…** → open panel ("Import keymap.json") → `editor.load(from:)`
      (`:41-51`).
- [ ] **Export…** → save panel ("Export keymap", `keymap.json`) →
      `editor.exportKeymap(to:)` (`:52-62`).
- [ ] **Advanced Mode** on/off → `editor.setShowAdvanced` (`:63-70`, `:76-78`).
- [ ] Tooltips "New", "Open", "Save", "Save As", "Import", "Export" — replaced
      by menu item titles (MG-3).

### 1.3 Icon rail (`IconRailView.swift`, `UIStyle.swift:204-239`)

- [ ] Five 40×40 rounded (radius 9) buttons, 16 apart, 16 top/bottom padding,
      in a 64-wide `Chrome.bar` column: **Keymap** (key), **Designs**,
      **Themes**, **Device**, **Macros** — each with that tooltip.
- [ ] Active: `glassActiveFill` tile and the *dark* (white) icon variant
      whatever the scheme; inactive: `glassFill` and the scheme's icon.
- [ ] Missing PNG → fallback label (KEY/DSN/THM/DEV/MAC), 11 pt semibold.

### 1.4 Status bar (`StatusBarView.swift`)

- [ ] 26 high, `Chrome.bar`, 11 pt `textTertiary`, 16 side padding, items 16
      apart: 7-pt dot (`connectedDot`/`disconnectedDot`) + "USB Connected" /
      "USB Disconnected"; "<design> · R×C"; "N layers"; "fw v0.9.0".
- [ ] Macro warning (not in MACROS mode): "Macros may not fit (estimated)"
      (regular, tertiary) or "Macros won't fit" (semibold, `dangerText`), tooltip
      = the full block reason (`:73-78`).
- [ ] Trailing "<file> — unsaved changes" when dirty.
- [ ] `editor.refreshDeviceStatus()` on appear (`:49-51`).

### 1.5 KEY mode

List column (`KeyModeViews.swift:8-168`), 260 wide, `Chrome.column`,
scrolling, 12/10 padding, sections 18 apart:
- [ ] DESIGNS: a row per design — name (12 pt, semibold + `accent` when
      active), trailing "R×C" (11 pt tertiary), `accentWash` radius-6 fill when
      active; click → select design (also re-seeds the DSN draft).
- [ ] THEMES: a row per theme — 10-pt dot in the theme's accent, name; click →
      select theme (re-seeds the THM draft).
- [ ] LAYERS header with a trailing 20×20 "+" chip (adds a layer; dimmed and
      inert at `EditorState.maxLayerCount`).
- [ ] A row per layer: "⋮⋮", "Layer n" (+ " — Base" for 0); click → current
      layer; on hover (not layer 0) a trailing trash glyph → alert "Delete
      Layer n?" with **Delete** / **Cancel**.

Main (`KeyModeViews.swift:172-219`), `Chrome.canvas`, padding 20:
- [ ] The board in a vertical scroll area (min 240 high): one row per design
      row, 6 apart; keycaps 46 high, width `units × 46 + (units−1) × 10`, 10
      apart, radius 6, fill `theme.background(for: token)`, label 12 pt in
      `theme.keyText`; a macro token shows the macro's name
      (`KeyCapView.swift`, `KeyboardBoardView.swift`).
- [ ] Board card: the theme's background colour, radius 10.
- [ ] Inspected key: 2-pt `accent` ring. Click a key → inspect it.
- [ ] Palette drawer below the board, served first (`layoutPriority`), min 260,
      max `PaletteDrawerView.maxHeight`, `Chrome.surface` radius 10, scrolling
      vertically (`PaletteDrawerView.swift:137-155`):
  - [ ] LAYERS & SPECIAL first: boxed layer picker (− n + → MO(n) TG(n);
        n clamped to `0…maxAssignableLayerIndex`), then trans, none,
        toggle_conn chips.
  - [ ] Every `KeyName.allGroups` section, Modifiers inserted after
        Navigation, titles 10-pt bold uppercase tertiary, chips chunked at most
        13 per row (`chipsPerRow`, pinned by `PaletteDrawerLayoutTests`).
  - [ ] MACROS: up to 13 macro chips, "+N more", or "No macros yet.".
  - [ ] Chip 44×26, radius 4, `chipBackground`, 1-pt `chipBorder`, label 11 pt.
- [ ] Placing an action on a key — **changed by decision** (§2.2 W5): drag a
      chip onto a key; clicking a chip assigns it to the inspected key.

Inspector (`KeyModeViews.swift:225-399`), 300 wide, padding 14:
- [ ] **Key / Matrix / Theme** tabs (a segmented `Picker`, §2.2 W8).
- [ ] Key: label 20 pt semibold ("—" if empty); "<canonical> · layer n";
      Advanced on → Row · Col, Row GPIO, Col GPIO, Driven axis, Canonical
      (monospaced); off → Row · Col only; **Clear** (and **Reassign**, see
      §2.2 W5); "No key selected" when none.
- [ ] Matrix: design name, "R rows · C cols", Rows: …, Cols: …, "Columns/Rows
      are driven".
- [ ] Theme: theme name, eight swatch rows (14-pt swatch with 1-pt
      `dividerLight` ring, label, hex monospaced 10 pt).

### 1.6 DSN mode

- [ ] List (`DesignModeViews.swift:6-76`): DESIGNS rows (as KEY), "+ New
      Design…" (13 pt accent, click → blank draft); MATRIX GPIO: "Rows: …",
      "Cols: …", "Columns are driven" checkbox (edits the draft).
- [ ] Main (`DesignGridEditorView.swift`): header on `surface` — "Name:" +
      name field, **+ Row**, **− Row**, **+ Col**, **− Col** pills; the grid on
      black in a scroll area, padding 20 — cells 44 high, width
      `w × 52 + (w−1) × 4` (a gap is 52 wide, black, "×"), radius 6, width text
      ("1", "1.25", …), selected 2-pt accent ring, click selects
      (`DesignCellView.swift`); footer on `surface` — "Selected (r, c):" + width
      presets 1, 1.25, 1.5, 1.75, 2, 2.25, 2.75 + "Gap" toggle, or "Select a cell
      to edit its width". Row/col removal clears an out-of-range selection.
- [ ] Inspector (`DesignModeViews.swift:80-109`): "Design actions",
      "R rows · C cols · <name> matrix", **Save Design** (primary),
      **Duplicate…**, **Delete** (destructive, disabled for an unsaved draft).

### 1.7 THM mode

- [ ] List (`ThemeModeViews.swift:6-67`): THEMES rows, "+ New Theme…"; COLOR
      ROLES: eight `ThemeSwatchField`s — Background, Key background, Font colour,
      Modifier keys, Layer keys, Special keys, Empty keys, Accent / selection —
      18-pt swatch, ring `dividerLight` (2-pt red when the hex is invalid),
      label, `#RRGGBB` field 76 wide monospaced 10 pt.
- [ ] Main (`:72-95`): the board rendered with the draft theme, read-only;
      "Live preview — updates as color roles change".
- [ ] Inspector (`:99-129`): "Theme actions", "Editing: <name>", **Save Theme**
      (primary), **Duplicate…**, **Import…** (open panel "Import theme JSON"),
      **Export…** (save panel "Export theme", "<name>.json").

### 1.8 DEV mode (`DeviceModeViews.swift`)

- [ ] List: TRANSPORTS — "USB (RP2040)" card (dot, "Connected"/"Not
      connected"); macOS: "BLE (ESP32-C6)" card — dot `connectedDot` (ready) /
      `dangerText` (connected, failed) / `disconnectedDot`, headline
      ("Connected", "Linked — service missing", "Unavailable", "Not
      connected"), the state's summary line. Cards: `surface`, radius 8, 1-pt
      `dividerLight` border, padding 10.
- [ ] Main: 14-pt status dot; headline 20 pt ("Connected via USB", "Connected
      via BLE", "Linked — upload service missing", the BLE summary, "Not
      connected"); "<design> · <MCU> · fw v0.9.0"; **Send to Device** /
      "Sending…" (primary, 180 wide, disabled while sending); macOS **Test
      Connection**; progress ("Starting upload…", "Sending chunk i of n…",
      "Committing…"); "Last sent just now / Ns ago / Nm ago / Nh ago".
- [ ] On appear: `refreshDeviceStatus()` + `DeviceMonitor.shared.start`; on
      disappear: `DeviceMonitor.shared.stop()` (`:215-221`).
- [ ] Inspector: "Device info" — Board, MCU, Matrix, Firmware, Layers on
      device; macOS: BLE, Peripheral, Signal ("n dBm"), Max write ("n B").

### 1.9 MACROS mode — library (`MacroLibraryView.swift`, `MacroLibraryRowView.swift`)

- [ ] Whole body (no list or inspector column), `Chrome.canvas`.
- [ ] Header: "Macros" 19 pt semibold; budget summary (11 pt tertiary);
      "Search macros" field (180); collection picker (140: All + every
      collection in use; a stale selection reads All); **Record new**
      (disabled, tooltip "Recording macros from the board isn't implemented
      yet."); **Import** (open panel "Import macro JSON"); **New macro**
      (accent).
- [ ] Capacity banner: block reason, 11 pt semibold `dangerText` on
      `dangerText` @ 0.12.
- [ ] Column headings MACRO 240, TRIGGER 130, STEPS 90, BYTES 90, COLLECTION
      130, ON 60.
- [ ] Row (`column` fill, radius 6, min height 40 / 64 with a warning):
      name (semibold) + disabled-and-bound warning (10 pt danger, 2 lines);
      trigger "RnCn"/"Unbound"; steps; bytes (danger when over capacity);
      collection field (writes through; spaces survive the normaliser);
      enabled toggle (tooltip "Disabled macros aren't uploaded, and free their
      bytes."); ⧉ duplicate, ↑ export (save panel "Export macro",
      "<name>.json"), trash delete — tooltips "Duplicate this macro", "Export
      this macro to a file", "Delete this macro"; clicking the informational
      cells opens the macro; a disabled macro's informational cells dimmed to
      0.55.
- [ ] Editing a collection clears an active collection filter
      (`MacroLibraryView.swift:330-335`).
- [ ] Delete: bound → alert naming key and layer, **Delete Anyway** /
      **Cancel**; unbound → "Delete “name”?" **Delete** / **Cancel**.
- [ ] Empty: "No macros yet. Create one to place it on a key." / "No macros
      match this search or collection.".

### 1.10 MACROS mode — step editor

List column (`MacroEditorViews.swift:73-225`), 212 wide, padding 14/12:
- [ ] ADD STEP: five rows (36 high, `chipBackground`, radius 6) — 28×28 badge
      KEY/TXT/DLY/LYR/RPT filled with the active theme's key/empty/modifier/
      layer background (RPT: `pillBackground`), text `keyText`; label
      Keystroke / Type text / Delay / Switch layer / Repeat block; click →
      insert after the selection.
- [ ] CAPTURE: "Record from board" disabled (tooltip as above) + "Recording
      from the board isn't available yet.".
- [ ] SLOT: 5-high track (`dividerLight`) with a fill (`accent`, `dangerText`
      when it cannot flash) at `fillFraction`, summary label, block reason.
- [ ] **Back to library**.

Main (`ContentView.swift:140-191`, `MacroEditorViews.swift:253-285`,
`MacroStepRowView.swift`), `Chrome.canvas`:
- [ ] Canvas header: macro name 19 pt + `canvasSummary` monospaced 12 pt;
      **Test run** (tooltip "Walks the macro's steps and shows the timing trace
      in the inspector. Doesn't send keystrokes."; switches the inspector to
      Timing); **Save** (accent; closes the editor).
- [ ] "Select a step to reorder or delete" (11 pt tertiary).
- [ ] Step rows, 6 apart, scrolling: ▲ ▼ (8 pt bold), then a card (radius 7;
      selected `accentWash` + `accent` border, else `column` + `dividerLight`)
      with index (mono), 30×18 type badge, payload summary, trailing metadata
      (mono); trailing ✕ delete. Click card → select.
- [ ] Append zone "Add a step" (44 high) — appends a keystroke step
      (§2.2 W6 adds dropping a step type on it).

Inspector (`MacroInspectorView.swift`), 248 wide, padding 14/15, scrolling:
- [ ] **Step / Macro / Timing** tabs (segmented, shared
      `editor.macroInspectorTab`).
- [ ] Step tab, per step type: keystroke — "Key" + current key + key chooser,
      "Modifiers" (8 multi-select chips, 4 per row), "Hold" slider 10…500
      quantised to 10 ms + "n ms"; text — `TextEditor` 80 high, "Typing speed"
      slider 10…100 + "n ms/char"; delay — slider 0…5000 + "n ms"; layer —
      Operation (Momentary/Toggle), Layer (0…max), the MO(0) warning text;
      repeat — count slider 1…20 + "n×", "N step(s) inside" list (rows reused,
      ▲▼✕) or "No steps yet -- add one below.", nested ADD STEP (no RPT; adding
      opens the new step), nested editor "Step i of n" + "Back to list" +
      **Delete step**; raw — "Unsupported step (kept on save)"; **Delete step**
      (destructive); "Select a step to edit it." when none.
- [ ] Macro tab: NAME field; BOUND KEY "Layer n · RnCn" / "Unbound".
- [ ] Timing tab: ESTIMATED DURATION (18 pt); PER STEP payload + "n ms" rows;
      "Test run estimates timing only. It doesn't send keystrokes.".

### 1.11 Icons, colours, shortcuts

- [ ] Eleven icons × light/dark PNGs (`Resources/macOS/Icons/`), every
      `AppIcon` case resolvable (`IconLoaderTests`). Five are drawn (rail);
      six become unused by MG-3.
- [ ] Every colour in §3, light and dark.
- [ ] Shortcuts: today the app binds none of its own. **New by decision**:
      ⌘N, ⌘O, ⌘S, ⇧⌘S on the File menu; the standard AppKit menu (About,
      Hide, Quit, Close, Edit, Window) comes with every MetalUI app.

---

## 2. Construct map

### 2.1 SwiftCrossUI constructs → MetalUI

The vocabulary is the **legacy** one (gap MG-1): `Row`/`Column`/`Box`/`Stack`/
`ScrollView`/`Text` with `Pixels`, as `metalui new` and the demos write it.

| SwiftCrossUI | where | MetalUI |
|---|---|---|
| `import DefaultBackend`, `@main struct …: App`, `WindowGroup`, `.defaultSize` | `App.swift:1-17` | `Sources/SMKConfigurator/main.swift`, **top-level code**: `let app = try App()`; `let window = try app.openWindow(title:size:minSize:) { RootView(editor:) }`; `app.commands { … }`; `app.run()`. Never `@main`/async main — an awaited file dialog's continuation would never run (`docs/getting-started.md`, `SV-H`) |
| `.commands { CommandMenu("View") { Menu("Appearance") { Toggle… } } }` | `App.swift:18-32` | `app.commands { CommandGroup(replacing: .newItem) { …file items… }; CommandMenu("View") { Toggle("Advanced Mode", …); Menu("Appearance") { ForEach-free three `Toggle`s } } }` — `Toggle` in a menu is a checked item |
| `.preferredColorScheme(editor.appearanceMode.colorScheme)` | `App.swift:12` | the same modifier on the root's content (window-wide, sets `NSWindow.appearance`); `AppearanceMode.colorScheme` moves to an app-side extension over MetalUI's `ColorScheme` |
| `@ObservableObject class EditorState` (SwiftCrossUI macro) | `EditorState.swift:87-88` | `@Observable` (`import Observation`) — the whole frame build is tracked, so property reads in `content` redraw |
| `@Environment(EditorState.self) var editor`, `.environment(editor)` | every view; `App.swift:11` | `let editor: EditorState` stored on each `Component`, passed down (MG-2) |
| `@Environment(\.colorScheme)` + `Chrome(scheme:)` | every view | palette keys resolve per scheme by themselves (§3): `Chrome.textPrimary` etc. are static `Color`s; only `IconLoader` still reads `@Environment(\.colorScheme)` |
| `struct X: View { var body: some View }` | every view | `struct X: Component { var content: some ElementGroup }`; a pane returns **one** container with its frame/background inside `content` (a `.frame` on a multi-member `Component` frames each member, divergence 56) |
| `VStack(alignment:spacing:)` / `HStack(spacing:)` | everywhere | `Column(gap: Pixels(s)) {…}.alignItems(.flexStart)` / `Row(gap: Pixels(s))`; **no `spacing:` was 8 in SwiftUI, write `Pixels(8)`** (divergence 52); `.alignItems` before `.padding` |
| `ZStack(alignment:)` | rows, cards | mostly deleted (§2.2 W1); where a real overlay remains, `Stack(alignment:)` or `.overlay` |
| `Spacer()` / `Spacer(minLength: 0)` | everywhere | `Spacer()` |
| `Text(…).font(.system(size:weight:design:)).foregroundColor(c)` | everywhere | the same spellings on legacy `Text` (`.font(Font)`, `.fontWeight`, `.foregroundColor(Color)`), `.lineLimit(2)` |
| `.padding(EdgeInsets(top:bottom:leading:trailing:))`, `.padding(n)`, `.padding(.horizontal, n)` | everywhere | `.padding(Pixels(n))` / `.padding(Edges(…))` — after container modifiers, before `.frame`/`.background` |
| `.frame(width:height:)`, `.frame(maxWidth: .infinity, maxHeight: .infinity)`, `.frame(minHeight:maxHeight:)` | everywhere | `.frame(…)` with `Pixels`; greedy is `Pixels(.infinity)`; a greedy box that must answer below its content: `.frame(minHeight: 0, maxHeight: .infinity)` (`LR-ET`) |
| `.layoutPriority(1)` on the palette | `KeyModeViews.swift:213` | the drawer gets an explicit `.frame(minHeight: 260, maxHeight: maxHeight)` and the board area is greedy — verify the drawer reaches its max in a tall window; otherwise MG entry |
| `.background(color)`, `.cornerRadius(r)`, `.background(RoundedRectangle(…).fill(c))`, `.overlay { RoundedRectangle.stroke }` | everywhere | `.background(color).cornerRadius(Pixels(r))` and `.border(color, width:)` (legacy border follows the radius, divergence 49) |
| `RoundedRectangle(cornerRadius:).fill`, `Circle().fill(...).frame` | swatches, dots, slot meter | the same shapes (`RoundedRectangle(cornerRadius: Pixels(r))`, `Circle()`), `.fill(color)`, `.frame` |
| `chrome.divider.frame(height: 2)`, `Divider()` | `ContentView.swift:56-66`, inspectors | `Divider()` (1 pt, the theme's `.separator`, divergence 127 — the window themes set `.separator` to `Chrome.divider`'s values, §3.3); the 2-pt line under the titlebar goes with the titlebar |
| `ScrollView { }`, `ScrollView(.vertical)` | columns, board, palette, inspector | legacy `ScrollView(.vertical) { }` (takes its parent's cross size, divergence 54) |
| `ScrollView(.horizontal)` inside a vertical one | key chooser, `MacroInspectorView.swift:631` | gone: the key chooser becomes a menu picker (MG-8) |
| `ForEach(…, id: \.self)` / `ForEach(identifiable)` | everywhere | `ForEach` (keyed), or a `for` in the builder |
| `TextField(placeholder, text: Binding)` + `.font` | name, hex, search, collection fields | `TextField(placeholder, text: Binding)`, `.font(.system(size:design:))` (`TextModifiers.swift:181`) |
| `TextEditor(text:)` | text step | `TextEditor(text: Binding)` `.frame(height: 80)` |
| `Toggle("", isOn:).toggleStyle(.switch)` / `.checkbox` | titlebar, library row, DSN | `Toggle(title, isOn:)` — a checkbox (MG-4) |
| `Slider(value: Binding<Int>, in:)` | inspector, 4 sites | `Slider(value: Binding<Double>, in:, step: 10)` over an `Int` adapter, still quantised by `MacroStep.quantizedToTick` |
| `Picker(of: [T], selection: Binding<T?>)` | collection filter, layer op, layer index | `Picker(title, selection: Binding<T>) { for … { Text(…).tag(value) } }`, `.pickerStyle(.menu)` for the collection filter and layer index; layer op segmented |
| `@Environment(\.chooseFile)` / `chooseFileSaveDestination` | titlebar, `ContentView.swift:285-306`, `MacroLibraryView.swift:337-395` | `@Environment(\.fileDialogs)` (or `window.fileDialogs` in a command): `try await dialogs.openFiles(allowedContentTypes: [.json])`, `saveFile(contentTypes: [.json], defaultFilename:)` inside `Task { @MainActor in … }`; `[]`/`nil` is a cancel (no start directory or title, MG-5) |
| `@Environment(\.presentAlert)` with buttons | `ContentView.swift:79`, `KeyModeViews.swift:67`, `MacroLibraryView.swift:407-426` | `.alert(_:isPresented:presenting:actions:message:)` with `Button(…, role: .destructive/.cancel)`, declared inside a `Component` (alert actions are evaluated at layout, `SV-AK`); presentation state is `@State`, written from input |
| `.onChange(of: editor.loadError)` + `presentAlert` | `ContentView.swift:76-82` | `.onChange(of: editor.loadError) { showLoadError = editor.loadError != nil }` + `.alert("…", isPresented: $showLoadError, presenting: editor.loadError) { _ in Button("OK") { editor.loadError = nil } }` |
| `.onAppear { }` / `.onDisappear { }` | ContentView, status bar, DEV main | the same; **write `Self`-returning legacy decorations before them** (divergence 120); the window root cannot be a lifecycle scope — wrap in a `Column` |
| `.onHover { }` | layer rows | `.onHover { inside in … }` on the row (`Self` on a `StyledElement`) |
| `.help(text)` | 11 sites | `.help(text)` (drawn tooltip after 1 s, divergence 113) |
| `.onTapGesture` on a plain view | link texts ("+ New Design…", "Back to list") | `Button { } label: { Text(…) }.buttonStyle(.plain)`, or `.onClick { }` on the `Text` |
| `Image(url).resizable().frame` | rail | `Image(decorative: bitmap, scale: 3).resizable().frame(…)` from the cached `ImageBitmap` (MG-10) |
| `Color.hex("#…", opacity:)` | `UIStyle.swift:49-63` | kept as an app helper over `Color(red:green:blue:opacity:)` (gamma sRGB, like SwiftUI) |
| `ThemeColor.color: Color`, `KeyboardTheme.background(for:) -> Color` | `KeyboardTheme.swift:14-23`, `:51-62` | `color` moves verbatim into `Views/ThemeColor+MetalUI.swift`; `background(for:)` stays in the model returning a `ThemeColor` (call sites add `.color`), so `Model/` has no UI type (§4.3) |
| `Bundle.module` icon URLs | `AppIcon.swift:46-54` | unchanged (`Resources/macOS/Icons` copied as before) |

### 2.2 SwiftCrossUI workarounds — deleted, not ported

| # | workaround | where | replacement |
|---|---|---|---|
| W1 | **Fake buttons**: `TapTarget` = `ZStack` of a filled `RoundedRectangle` + label + `.onTapGesture` | `UIStyle.swift:85-121`; users `ToolbarPill` `:136`, `ToolbarIconButton` `:170`, `RailButton` `:204`, `InspectorButton` `:244`, `KeyModeViews.swift:127`, `:254`, `PaletteDrawerView.swift:225-240`, `MacroEditorViews.swift:97`, `:132`, `:200`, `MacroInspectorView.swift:61`, `ContentView.swift:180` | a real `Button { } label: { }` with `.buttonStyle(.plain)` and the look as decorations (`.padding`, `.frame`, `.background`, `.cornerRadius`, `.border`) — focusable, Space/Return, VoiceOver press, pressed wash for free. Kept as three small styles: `PillButton` (toolbar pill, accent/plain), `InspectorButton` (primary/destructive), `RailButton` |
| W2 | `TapTarget`'s "no `if` inside the `ZStack`, always stroke a `.clear` border, a circle is half-side radius" rule | `UIStyle.swift:98-120`, `:89-97` | deleted with W1 |
| W3 | **Per-colour fading** for "disabled" (`fade = isEnabled ? 1 : 0.4` applied to every colour) | `UIStyle.swift:146-155`, `:255-266`, `KeyModeViews.swift:125-136`, `MacroEditorViews.swift:132-137` | `.disabled(!isEnabled)` — the one gate, and `Button`'s built-in 0.5 disabled look; "Record from board"/"Record new" become real disabled `Button`s |
| W4 | **Per-colour row dimming** (`dimmed(_:)`, no view `.opacity`) | `MacroLibraryRowView.swift:118-128` | `.opacity(0.55)` on the informational cells' container (controls and the warning stay full strength, as today) |
| W5 | **Click-to-arm, click-to-place** instead of drag and drop (`editor.selectedToken`, armed ring, Reassign) | `KeyCapView.swift:3-7`, `:42`, `:65-72`; `PaletteDrawerView.swift:7-8`, `:306-322`; `KeyModeViews.swift:307-313` | `PaletteChip` `.draggable(token.canonicalString)` and `KeyCapView` `.dropDestination(for: String.self) { … editor.assign(ActionToken(…), row:col:) }` with an accent ring while targeted; **clicking a chip assigns it to the inspected key** (`editor.selectedKeyPosition`), so the Reassign button and the armed ring go. `EditorState.selectedToken`/`toggleSelection`/`reassignSelectedKey` stay in the model (tests use them) but no view arms. *Decision to confirm with the user at lane 2's report.* |
| W6 | "Add a step" card as the **drag-to-append substitute** | `ContentView.swift:174-191` | the card is a `.dropDestination(for: String.self)` for a `MacroStepType.rawValue` dragged from the ADD STEP rows (`.draggable(type.rawValue)`) and still appends a keystroke on click; tap-to-insert-after-selection on the palette rows stays (a real feature, not a substitute) |
| W7 | **Hand-built tab rows** (`ForEach` of sibling `TapTarget`s) | `KeyModeViews.swift:251-266`, `MacroInspectorView.swift:58-74` | `Picker("", selection:) { Text("Key").tag(…) … }` — `.automatic` is segmented in MetalUI (divergence 81) |
| W8 | **The custom titlebar**: content drawn under the traffic lights as a toolbar | `TitlebarView.swift` (whole file), `ContentView.swift:55-56`, `chromeHeight` `:36` | deleted; File menu + View ▸ Advanced Mode (MG-3); `chromeHeight` becomes status bar 26 + divider 1 |
| W9 | **Sibling-not-nested tap targets** (a second tap target cannot live inside a first; hover must be chained on the same view in front of the tap) | `KeyModeViews.swift:16-24`, `:48-55`, `:139-146`; `MacroStepRowView.swift:6-15`; `MacroLibraryRowView.swift:4-33` | nested `Button`s/`onClick`s are fine: one hitbox list, the topmost target wins (MetalUI CLAUDE.md "Hit testing") — the first lane to nest one confirms it at a launch and files an MG entry if not. Rows become one container with the controls inside; `.onHover` on the row; hover-revealed trash comes back for layer rows |
| W10 | `.onTapGesture` before `.padding` so padding is not hittable | `MacroLibraryRowView.swift:231-237` | a plain `Button` sized by its own label; padding outside it |
| W11 | `Color.clear` filler + pinned frame to make the informational region tappable | `MacroLibraryRowView.swift:59-79` | `.onClick` on the cells' `Row` — a legacy handler hits its element's whole frame (divergence 41) |
| W12 | `CollectionFilterOption.description` exists because `Picker` labels options with `"\(value)"`; `layerOpLabels` label table for the same reason | `MacroLibraryView.swift:137-146`, `MacroInspectorView.swift:363-368` | `Picker` options are `Text(…).tag(value)`: the layer op picker tags `LayerOp` directly, the table goes. `CollectionFilterOption` itself stays (its `.all` vs `.named("All")` distinction and `selected(for:among:)` are tested, `MacroLibraryFilterTests`) |
| W13 | Optional-selection `Picker` bindings with `guard let` | `MacroLibraryView.swift:284-287`, `MacroInspectorView.swift:407-410` | MetalUI's `Picker` selection is non-optional |
| W14 | Hex text field because there is no colour picker | `ThemeSwatchField.swift:3-7` | **kept** — MetalUI has none either (MG-7) |
| W15 | Layer-index −/+ built from two 20×20 `TapTarget`s around a number | `PaletteDrawerView.swift:223-246` | `Stepper("", value: $pendingLayerIndex, in: 0...maxAssignableLayerIndex)` beside "n → MO(n) TG(n)"; the box/border look stays |
| W16 | Key chooser as grouped chips in horizontal scroll rows (a flat `Picker` printed `"\(value)"`) | `MacroInspectorView.swift:604-655`, `:693-723` | `Picker("Key", selection:) { for key … Text("\(group) — \(key.displayLabel)").tag(key) }.pickerStyle(.menu)` (user's note; MG-8). The modifier multi-select keeps its eight chips (now `Button`s) |

Kept on purpose (not SwiftCrossUI workarounds, or tested behaviour):
fixed-width SLOT track (`MacroEditorViews.swift:145-152`, a known width);
chunked palette rows (`PaletteDrawerView.swift:189-198`, `chipsPerRow` is
pinned by tests); the collection field's write-through + `collectionText`
draft rule (`MacroLibraryRowView.swift:153-224`, tested) — a lane may move the
commit to `onSubmit`/focus loss through `@FocusState` only if the tests stay
green; translucent "glass" fills (MG-9).

---

## 3. The palette

### 3.1 App palette keys (chrome)

One `ThemeColorKey` per chrome token, `defaultValue = Color(light:dark:)`, in
`Views/Palette.swift`; read as static `Color`s on a `Chrome` namespace
(`Chrome.bar` = `Color(ChromeKeys.Bar.self)`), so a call site reads as it did
(`chrome.textPrimary` → `Chrome.textPrimary`). Values are `UIStyle.swift:5-47`,
unchanged.

| key | used for | light | dark |
|---|---|---|---|
| `bar` | rail, status bar | `#F6F6F7` | `#2B2B2D` |
| `canvas` | main content | `#ECECEE` | `#1E1E20` |
| `column` | list/inspector columns, library rows, step cards | `#FBFBFC` | `#252527` |
| `divider` | pane dividers (→ theme `.separator`, §3.3) | `#E3E3E5` | `#3A3A3C` |
| `dividerLight` | swatch rings, cards, slot track, step borders | `#DDDDDD` | `#333335` |
| `surface` | palette drawer, DSN header/footer, cards, DSN cell | `#FFFFFF` | `#2C2C2E` |
| `accent` | selection text, rings, primary buttons, links | `#007AFF` | `#0A84FF` |
| `accentWash` | selected row/card fill | `#007AFF` @ 0.12 | `#0A84FF` @ 0.18 |
| `textPrimary` | body text | black @ 0.85 | white @ 0.85 |
| `textSecondary` | secondary text | black @ 0.60 | white @ 0.60 |
| `textTertiary` | captions, headers | black @ 0.45 | white @ 0.45 |
| `pillBackground` | pills, inspector buttons | `#ECEEF0` | `#3A3A3C` |
| `chipBackground` | palette/modifier chips, step-type rows, badges | `#F2F2F4` | `#323234` |
| `chipBorder` | chip hairlines, layer-picker box | `#E0E0E2` | `#48484A` |
| `glassFill` | inactive rail tile | `#ECEEF0` @ 0.97 | `#3A3A3C` @ 0.90 |
| `glassActiveFill` | active rail tile | `#007AFF` @ 0.75 | `#0A84FF` @ 0.80 |
| `dangerText` | warnings, destructive labels, delete glyphs | `#D92C2C` | `#FF453A` |
| `connectedDot` | connected status dots (was `toggleOn`) | `#34C759` | `#30D158` |
| `disconnectedDot` | disconnected dots | `#B0B0B4` | `#6E6E73` |

Dropped: `toggleOff` (`#E2E2E5`/`#48484A`) — no reader (`grep -c chrome.toggleOff` = 0);
`toggleOn` survives as `connectedDot`'s value.

Opacity at the call site (`Color.opacity` multiplies, `CR-G`), kept as written:
`dangerText` @ 0.12 (capacity banner, `MacroLibraryView.swift:365`),
`pillBackground` @ 0.6 (append zone, `ContentView.swift:181`),
`chipBackground` @ 0.5 (layer-picker box, `PaletteDrawerView.swift:248`).

### 3.2 Literal colours

| literal | where | why literal |
|---|---|---|
| `Color.white` | text on an accent fill (pills, primary buttons, active tab text, active rail fallback label) | the same in both schemes |
| `Color.black` | DSN grid background (`DesignGridEditorView.swift:35`), gap cell (`DesignCellView.swift:22`) | the editor's "physical board" canvas, scheme-independent |
| `Color.red` | invalid-hex swatch ring (`ThemeSwatchField.swift:23`) | error marker; MetalUI's `.red` is the macOS system red (divergence 117), close to SwiftCrossUI's |
| `Color(red: 1, green: 0, blue: 1)` | malformed hex (`ThemeColor.color`, `Color.hex`) | deliberate "bad hex" magenta |
| `Color(red: 1, green: 0, blue: 0)` | `.raw` token keycap (`KeyboardTheme.swift:59`) | unknown-token marker |
| `Color.clear` | unselected row fill | dropped: no fill at all |

### 3.3 Data colours (not chrome)

The keyboard themes' eight roles (`KeyboardTheme` built-ins and user themes,
`ThemeColor.hex`), keycap fills (`background(for:)`), theme-row accent dots,
THM swatches and live preview, the ADD STEP badges (`MacroStepType` →
theme roles) stay **literal `Color` values computed from the model** — they
are user data and must not change with the app's scheme.

### 3.4 MetalUI's own tokens

MetalUI's controls (checkbox, segmented picker, slider, focus ring, `Divider`,
menus) paint from the window `Theme`'s built-in tokens. Lane 1 sets
`app.lightTheme`/`app.darkTheme` so they agree with the palette: `.accent` =
`accent`, `.separator` = `divider`, `.surface` = `surface`, `.textPrimary` =
black/white (the palette's 0.85 alpha stays on the app's own text). Nothing
else is overridden.

---

## 4. Target split and CI

### 4.1 Ruling: one source tree, a per-platform target named `SMKConfigurator`

The preferred shape was a separate UI-free library (`SMKCore`) plus a macOS app
target. **The code rules it out**: a second module can only see `package`/
`public` declarations, so every model declaration the views use would need an
access modifier — including the two **generated** files,
`Model/KeyCodesGenerated.swift` (`KeyName`, ~250 cases, from
`~/esp/SMK/generate_keycodes.sh`) and `Device/BLEUploadUUIDs.swift` (from
`~/esp/SMK/generate_ble_uuids.sh`). Both are emitted without access modifiers
by scripts in the firmware repo and committed byte-identical in both repos
("do not edit"); changing them means changing the firmware repo's generators,
outside this branch. `@testable import` from the app would break `-c release`.

So the package declares **one target named `SMKConfigurator` per platform**,
over the same `Sources/SMKConfigurator/` tree:

- **macOS**: an `executableTarget` with all of `Model/`, `Device/`, `Views/`
  and `main.swift`, depending on `MetalUI` and `CHidapi`, resources
  `.copy("Resources/macOS/Icons")` (the Windows/Linux icon trees excluded);
  test target `SMKConfiguratorTests` with every test file.
- **Linux, Windows**: a library `.target` with `exclude: ["Views", "main.swift",
  "Resources"]`, depending only on `CHidapi` — no UI dependency, MetalUI is not
  even declared there; test target `SMKConfiguratorTests` with
  `exclude: ["IconLoaderTests.swift", "ShellRenderTests.swift"]` (both import
  MetalUI, which is not declared there; `IconLoaderTests` also needs the
  bundled PNGs). **Every later test file that imports MetalUI joins this
  exclude list**, or Linux `swift test` and Windows `--build-tests` fail with
  `no such module 'MetalUI'`.

The MetalUI dependency and its URL exist only inside `#if os(macOS)` in
`Package.swift`, so Linux/Windows never resolve it (MetalUI's manifest is
tools-version 6.4; Linux CI's toolchain is 6.2 and never needs to read it).
**What enforces "Model/ and Device/ have no UI dependency"**: the Linux and
Windows builds compile those two directories alone; a `Model/` file that
imports MetalUI or names a view type fails there. Test files keep
`@testable import SMKConfigurator` unchanged on both shapes.

Consequences: pure view-logic types that tests or the model use move from
`Views/` into `Model/` (§4.3), so they exist on Linux too.

### 4.2 CI

- `linux-build.yml`: drop `libgtk-4-dev libgtk-3-dev` (SwiftCrossUI's), keep
  `clang libhidapi-dev`; keep `swift build --target SMKConfigurator` (now the
  library); **add `swift test`** (the model and device tests have never run on
  Linux — the lane reports what it cannot verify without pushing). Its comment
  about swift-winui goes.
- `windows-build.yml`: drop the "Pre-compile Macro Targets" step
  (`SwiftCrossUIMacrosPlugin` no longer exists); keep vcpkg hidapi and the
  build; add `swift build --build-tests` so the tests at least compile.
  Running them on Windows is a follow-up for the Linux/Windows item (paths
  such as `homeDirectoryForCurrentUser` and `UserDefaults` suites have never
  been exercised there).
- No push from any lane; CI is first exercised when the user pushes.

### 4.3 Model/Device edits forced by the port (all in lane 1)

The only changes inside `Model/` and `Device/`:

1. `EditorState.swift`: `import SwiftCrossUI` → `import Observation`;
   `@ObservableObject` → `@Observable`; the comments about the SwiftCrossUI
   macro skipping accessors updated; `AppearanceMode.colorScheme` removed
   (moves to `Views/`).
2. `KeyboardTheme.swift`: `import SwiftCrossUI` removed; `ThemeColor.color`
   moves verbatim to `Views/ThemeColor+MetalUI.swift`.
   `KeyboardTheme.background(for:)` **stays in the model** but returns the
   role's `ThemeColor` (`.raw` → `ThemeColor(hex: "#FF0000")`) instead of a
   `Color` — `KeyboardThemeTests.swift:52-61` calls it on every token (it
   discards the result, so the test is unchanged) and must compile on Linux;
   views write `theme.background(for: token).color`.
3. New `Model/` files holding view-logic types moved **verbatim** out of
   `Views/` (names unchanged unless stated): `MacroInspectorTab` (the model's
   `macroInspectorTab` property needs it), `MacroStepType` minus
   `badgeColor(theme:)` (which moves to a `Views/` extension), `MacroLibraryRow`,
   `MacroLibraryFilter`, `CollectionFilterOption`, `MacroLibraryColumn`,
   `DesignGridPosition`, `AppIcon` (enum + `fallbackLabel`; `IconLoader` stays
   in `Views/`), and `PaletteLayout` — `PaletteDrawerView`'s static layout
   members (`chipsPerRow`, `keySections`, `macroTokens(for:)`,
   `macroSectionHeight`, `maxHeight`, `minHeight` and their private constants)
   under a new name, since `PaletteDrawerView` becomes the `Component`.
   `MacroLibraryRowView.collectionText(draft:stored:)` becomes
   `MacroLibraryRow.collectionText(draft:stored:)`.
4. Tests: only references follow the moves — `PaletteDrawerView.` →
   `PaletteLayout.` (`KeyVocabularyTests.swift:94-118`,
   `MacroPaletteTests.swift:17-40`, `PaletteDrawerLayoutTests.swift`),
   `MacroLibraryRowView.collectionText` → `MacroLibraryRow.collectionText`
   (`MacroLibraryFilterTests.swift:179-194`), `import SwiftCrossUI` →
   `import MetalUI` (`IconLoaderTests.swift:2`). No assertion changes, no test
   deleted.

`Device/` is untouched. `DeviceMonitor`'s `Task` loop and
`EditorState.sendToDevice`'s `Task` write the model from main-actor tasks, not
from a phase — allowed (MetalUI's "write state from input, never from a
phase"); they run because `main.swift` calls `app.run()` from top-level code.

---

## 5. Lanes

Three **sequential** lanes, each on files the others do not touch. At the end
of every lane: `swift build` with 0 `error:`, `swift test` ≥ 225 tests all
passing (summary line recorded exactly; sum several if printed), a commit, and
— screen unlocked only — a launch of a few seconds to see the window, then
kill it. A MetalUI shortfall found in a lane is appended to the gaps file
(next id after the last `## MG-`) with its workaround, never patched in
MetalUI. Each lane's report names its decisions-to-confirm.

Shared rules for every lane: the legacy vocabulary (MG-1); every reusable piece
a `Component` taking `let editor: EditorState` where it reads the model
(MG-2); state written from input (button actions, `onChange`, `onAppear`),
never from `content`; `.id()` outermost; container/item modifiers before
`.padding`, `.frame`/background/corner radius after; no `GeometryReader`; the
window is macOS-only, so the 1 MB-stack composer rule (Windows) is noted for
the later SDL item, not applied.

### Lane 1 — dependency, target split, app shell, palette, shared styles

**Files (only these):** `Package.swift`, `Package.resolved`,
`.github/workflows/linux-build.yml`, `.github/workflows/windows-build.yml`;
`Sources/SMKConfigurator/App.swift` (deleted) → `main.swift` (new);
`Model/EditorState.swift`, `Model/KeyboardTheme.swift` (§4.3 only); new
`Model/MacroUITypes.swift` (`MacroInspectorTab`, `MacroStepType`),
`Model/MacroLibraryModel.swift` (`MacroLibraryRow`, `MacroLibraryFilter`,
`CollectionFilterOption`, `MacroLibraryColumn`), `Model/PaletteLayout.swift`,
`Model/AppIcon.swift`, `Model/DesignGridPosition.swift`; in `Views/`:
`UIStyle.swift` (rewritten: `PillButton`, `InspectorButton`, `RailButton`,
`SectionHeader`, `StatusDot`, `Color.hex`), new `Palette.swift` (§3 keys,
`Chrome` namespace, theme token overrides), new `AppCommands.swift` (File and
View menus), new `ThemeColor+MetalUI.swift` (incl. `MacroStepType.badgeColor`,
`AppearanceMode.colorScheme`), `AppIcon.swift` → `IconLoader.swift` (URL +
`ImageBitmap` cache), `ContentView.swift` (the shell, below),
`IconRailView.swift`, `StatusBarView.swift`, new `WindowMetrics.swift`
(`chromeHeight`, `boardMinHeight`, KEY content min/ideal heights, window
min/ideal sizes); **deleted**: `TitlebarView.swift` and every other
SwiftCrossUI view file — each replaced by a **placeholder file of the final
name** whose types have the final names and initialisers, rendering a centred
"<Pane> — not yet ported" text on the pane's background at the pane's width:
`KeyModeViews.swift` (`KeyListColumnView(editor:selectDesign:selectTheme:)`,
`KeyMainContentView(editor:)`, `KeyInspectorView(editor:)`),
`DesignModeViews.swift` (`DesignListColumnView(editor:draft:selectDesign:newDesign:)`,
`DesignInspectorView(draft:isExistingDesign:save:duplicate:delete:)`),
`DesignGridEditorView.swift` (`DesignGridEditorView(draft:selectedCell:)`),
`ThemeModeViews.swift` (`ThemeListColumnView(editor:draft:selectTheme:newTheme:)`,
`ThemeMainContentView(editor:draft:)`,
`ThemeInspectorView(draft:save:duplicate:importTheme:exportTheme:)`),
`DeviceModeViews.swift` (`DeviceListColumnView(editor:)`,
`DeviceMainContentView(editor:)`, `DeviceInspectorView(editor:)`),
`MacroLibraryView.swift` (`MacroLibraryView(editor:)`),
`MacroEditorViews.swift` (`MacroStepPaletteView(editor:)`,
`MacroCanvasHeaderView(editor:)`), `MacroInspectorView.swift`
(`MacroInspectorView(editor:)`), `MacroStepRowView.swift`
(`MacroStepRowView(step:index:isSelected:onSelect:onMoveUp:onMoveDown:onDelete:)`).
`KeyboardBoardView.swift`, `KeyCapView.swift`, `PaletteDrawerView.swift`,
`DesignCellView.swift`, `ThemeSwatchField.swift`, `MacroLibraryRowView.swift`
are deleted without a placeholder (only their pane uses them; the owning lane
recreates them). Tests: the reference renames of §4.3 item 4 only.

**What it builds.** `main.swift` (top-level: `EditorState`, `App`, theme token
overrides, `openWindow(title: "SMK Keymap Configurator", size: 1440 ×
idealWindowHeight, minSize: 1440 × minWindowHeight)`, `app.commands`,
`app.run()`); the root `Column` with `.preferredColorScheme`, the load-error
alert via `onChange(of: editor.loadError)`, the draft seeding `onAppear`;
`ContentView` with the rail, the three column switches over the placeholders
(and the macro-mode sub-states), the design/theme draft workspace functions,
theme import/export through `fileDialogs`, the macro editor's main column
composition (`macroEditorContent`: header, hint, step list over
`MacroStepRowView`, append zone — the append zone's drop target is lane 3's);
`Divider()` between panes; the real status bar and rail; the File menu (New,
Open…, Save, Save As…, Import…, Export… with ⌘N/⌘O/⌘S/⇧⌘S) and View menu
(Advanced Mode, Appearance ▸ Light/Dark/System) in `AppCommands.swift`.

**Done means:** SwiftCrossUI gone from `Package.swift`, `Package.resolved` and
every source (`grep -rn SwiftCrossUI Sources Tests` empty); MetalUI resolved at
the pinned revision; `swift build` 0 `error:`; `swift test` ≥ 225, all pass,
`BinaryFormatAgreementTests` among them; the app opens to the shell — rail
switches all five modes, each pane a visible placeholder, status bar live,
menus present, Appearance switches light/dark live, palette keys visibly change
with the scheme; gaps file appended for anything new.

**Lane 1 status (2026-10-06).** Landed as above. `swift build`: 0 `error:`,
no app warnings. `swift test`: `Test run with 228 tests in 25 suites passed`
(XCTest `Executed 0 tests`): the 225 baseline plus `ShellRenderTests` (3),
which opens a real window and draws the shell in every rail mode, both macro
sub-states and both schemes through the public `Window.drawFrameIfNeeded()`
(MG-12) — a layout trap fails it; mutation-checked (a `fatalError` in the DEV
inspector placeholder's body killed the run). Additions beyond the list:
`PaletteLayout` also exposes its chip metrics and `chunk(_:into:)` for lane 2;
`KeymapFileActions` (in `AppCommands.swift`) holds the dialog helpers
`ContentView`'s theme import/export reuse; `PanePlaceholder` (in
`UIStyle.swift`) goes with the last placeholder.
**Lane 1 fix pass (2026-10-06).** Linux/Windows test target now excludes
`ShellRenderTests.swift` too (§4.1; a Docker run of the previous tree failed
`--build-tests` with `no such module 'MetalUI'`). `ShellRenderTests` gained a
windowless test over the public `renderFrame` with `PortableTextSystem` +
`SystemFonts` (test-only product dependencies), and MG-12 was rewritten to
what that path really lacks. `swift test`: `Test run with 229 tests in 25
suites passed` (XCTest `Executed 0 tests`). The on-screen checks below move to
lane 2, which launches the app first with the screen unlocked. **Not seen**: the screen was
locked for the whole lane, so no launch — the visual "Done means" items (rail
switching, Appearance live, palette changing with the scheme, menus) are
unverified by eye; the render test proves only that every mode builds and lays
out without trapping, and `paletteFollowsTheScheme` that all 19 keys resolve
differently in light and dark. Lane 2 should launch first. Gaps: MG-11…MG-13.

### Lane 2 — KEY, DSN, THM and DEV panes

**Files (only these):** `Views/KeyModeViews.swift`,
`Views/PaletteDrawerView.swift` (new: the drawer `Component` reading
`PaletteLayout`, `PaletteChip`), `Views/KeyboardBoardView.swift` (new),
`Views/KeyCapView.swift` (new), `Views/DesignModeViews.swift`,
`Views/DesignGridEditorView.swift`, `Views/DesignCellView.swift` (new),
`Views/ThemeModeViews.swift`, `Views/ThemeSwatchField.swift` (new),
`Views/DeviceModeViews.swift`; optional new tests in
`Tests/SMKConfiguratorTests/` for logic it extracts (a new file per suite).

**What it builds.** §1.5–§1.8 in full: the KEY list (design/theme/layer rows,
"+" chip with `.disabled`, hover trash → `.alert(presenting:)` "Delete Layer
n?"), the board and keycaps (`.dropDestination`, inspect on click, accent
ring), the palette drawer (layer picker with `Stepper`, `.draggable` chips,
click-to-assign, MACROS strip), the KEY inspector (segmented tabs; Clear; the
Reassign decision of W5); DSN list/grid/footer/inspector; THM list with swatch
fields, live preview, inspector; DEV cards, main (Send/Test Connection,
progress, last sent; `DeviceMonitor` start/stop in `onAppear`/`onDisappear`),
inspector. Glyph rendering (⋮⋮, →, ×) checked; anything missing → MG entry.

**Done means:** every §1.5–§1.8 box ticked against a launch (each mode
visited in light and dark), placeholders for KEY/DSN/THM/DEV gone; drag a chip
onto a key changes it and marks the document dirty; `swift build` 0 `error:`;
`swift test` ≥ 225 all pass; W1, W3, W5, W7, W9, W15 gone from these files.

**Lane 2 status (2026-10-06).** §1.5–§1.8 built in the listed files; no
KEY/DSN/THM/DEV placeholder left. `swift build`: 0 `error:`. `swift test`:
`Test run with 247 tests in 30 suites passed` (XCTest `Executed 0 tests`) — 229
plus `PaneLogicTests` (14: drop payload round trip and raw-text refusal, a drop
marking the document dirty, DSN grid edits, key/cell sizes, DEV status text)
and `PaneRenderTests` (4: each pane headless in its edge states). Both are
macOS-only and join the Linux/Windows exclude list in `Package.swift` (§4.1).
Mutation: letting `PaletteDrop` accept raw text reddened "text dragged in from
another app is refused…".
- **Deleted, not ported:** W1 (every row, chip, key, cell, tab and link is a
  real `Button`), W3 (`.disabled` on "+" layer chip and Delete), W5 (drag a
  chip onto a key; a click on a chip assigns it to the inspected key; the
  armed ring and Reassign are gone — `EditorState.selectedToken` and friends
  stay, unused by views), W7 (segmented `Picker`), W9 (the hover trash is a
  button nested in the layer row's button), W15 (`Stepper`).
- **New shared pieces** (in `KeyModeViews.swift`): `pane { }` (type erasure,
  MG-15 — **lane 3's macro panes must wrap their content in it too**),
  `ListRowButton`, `DesignRow`, `ThemeRow`, `LinkButton`, `ListColumn`,
  `ListSection`, `InspectorColumn`, `InspectorHeading`, `DetailLine`,
  `LayerRow`, `ThemeSwatchRow`; `ThemeRole`/`Swatch` in `ThemeSwatchField.swift`;
  `PaletteDrop` in `KeyCapView.swift`; `DesignGridEditing` in
  `DesignGridEditorView.swift`; `DeviceTransportStatus`/`DeviceStatusText` in
  `DeviceModeViews.swift`.
- **Faithful, though §1.6 reads otherwise:** the 1.5 width preset is labelled
  "1.50", as the previous build's `%.2f` printed it.
- **Decision to confirm (W5):** Reassign is removed outright; a key changes
  by drag or by clicking a chip while the key is inspected.
- **Not seen:** the screen was locked for the whole lane
  (`CGSSessionScreenIsLocked` true), so no launch — no box of §1.5–§1.8 is
  ticked against the running app, the glyphs (⋮⋮ → × ✕) are unchecked, and
  dragging a chip onto a key is unverified as a gesture (MG-17); the tests
  prove each pane builds and lays out without trapping and the drop logic
  marks the document dirty. Lane 3 (or whoever next has the screen) launches
  first and checks these.
- **Gaps:** MG-14 (no `layoutPriority` on legacy stacks; the board area is
  capped at the board's height instead), MG-15 (the debug-build stack overflow
  that `pane { }` works around), MG-16, MG-17, MG-18.

### Lane 3 — MACROS mode, README, parity check

**Files (only these):** `Views/MacroLibraryView.swift`,
`Views/MacroLibraryRowView.swift` (new), `Views/MacroEditorViews.swift`
(`MacroStepPaletteView`, `MacroStepTypeRow`, `MacroCanvasHeaderView`),
`Views/MacroStepRowView.swift`, `Views/MacroInspectorView.swift`,
`ContentView.swift` **only** for the append zone's `.dropDestination` (W6) —
lane 1 leaves it a plain button; `README.md`; this plan's §1 ticks and the
gaps file; optional new test files.

**What it builds.** §1.9–§1.10: the library (search, collection menu picker,
Record new disabled, Import/Export macro via `fileDialogs`, New macro, capacity
banner, headings, rows with nested controls, 0.55 dimming, the two delete
alerts, empty states); the step editor's palette column (draggable step-type
rows, tap-to-insert, disabled Record from board, SLOT meter, Back to library),
canvas header (Test run, Save), step rows (▲▼, card, ✕), the append drop
zone; the inspector (segmented Step/Macro/Timing, every step editor with
`Slider`s over `Int` adapters, the menu-picker key chooser (W16), modifier
chips, layer op/index pickers, MO(0) warning, repeat-block nested editor,
macro name, bound key, timing). Then `README.md` rewritten for MetalUI
(build/run with plain `swift build`/`swift run`, macOS-only UI, the
library-only Linux/Windows CI, the gaps file), and the **final parity pass**:
every box in §1 ticked or moved to "changes by decision" with its reason.

**Done means:** no placeholder left (`grep -rn "not yet ported" Sources` empty);
§1 fully ticked; `swift build` 0 `error:`; `swift test` ≥ 225 all pass;
README describes the MetalUI app; gaps file final.

### Outside the lanes' file list (flagged, not done)

- The repo's `CLAUDE.md` describes SwiftCrossUI (build flags, `@ObservableObject`,
  `TapTarget`, `--build-system native`); it becomes stale at lane 1 and is not
  in any lane's file list — the user decides who rewrites it.
- Packaging: `Scripts/run.sh` + `Bundler.toml` (swift-bundler) carry the
  `NSBluetoothAlwaysUsageDescription` plist key CoreBluetooth needs. Whether
  swift-bundler copies `MetalUI_MetalUIRender.bundle` into
  `Contents/Resources` (MetalUI's `docs/packaging.md`, `AI-N`; `App.init`
  throws `ShaderLibraryError.resourceMissing` otherwise) is unverified;
  MetalUI's `metalui new` recipe (`scripts/bundle-macos.sh` + an `Info.plist`)
  is the alternative. Not in the lanes' files; `swift run` is unaffected.
- macOS builds need a Swift 6.4 toolchain (MetalUI's manifest), where
  SwiftCrossUI needed 6.2.
