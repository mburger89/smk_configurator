# MetalUI gaps found by the SMK configurator port

What MetalUI (pinned at `e54c3f65086b446d42b09bf6f2fdbf802f7ed52a`, its
`master` on 2026-10-06) could not express while porting this app, and what the
app does instead. Each entry: **what** is missing, **where** in the app it
bites, the **smallest app-side workaround** used, and a **severity**
(high = shapes the whole port, medium = a visible compromise, low = cosmetic
or an easy workaround). These feed MetalUI's to-do list; nothing here is
fixed in MetalUI by this branch.

A MetalUI *bug* (a trap, wrong layout, a crash) found during the port goes
here too, with a minimal reproduction, rather than being worked around
silently. Ids are `MG-<n>`, never reused.

Entries MG-1…MG-10 come from the planning survey (reading MetalUI's source and
docs against the app's 3,400 lines of views), before any port code was
written. Later lanes append.

---

## MG-1 — controls are not proposal elements, so SwiftUI stacks cannot hold them

- **What.** `HStack`/`VStack`/`ZStack` take `ProposalElementGroup` content,
  but `Button`, `Toggle`, `TextField`, `TextEditor`, `Picker`, `Slider`,
  `Stepper` and the legacy `Text` conform only to `Element`/`StyledElement`
  (`Sources/MetalUI/Button.swift:46`, `Toggle.swift:28`, `TextField.swift:20`,
  …; the conformance list is `ProposalElementGroup.swift:181-193`). Minimal
  reproduction: `HStack { Button("x") {} }` does not compile.
  `docs/migration.md` ("Migrate inside-out") states the rule; it is a
  framework fact, not a bug.
- **Where.** Every pane: almost every row in the app mixes text with a
  control (the status bar, every inspector, the macro library row, the DSN
  header and footer).
- **Workaround.** The whole app is written in the **legacy vocabulary** —
  `Row`/`Column`/`Box`/`Stack`/`ScrollView`/`Text`, `Pixels`, the
  `StyledElement` modifiers — the vocabulary `metalui new`'s starter and the
  `MetalUIDemoContent` controls/services demos use. SwiftUI-vocabulary
  elements (`Image`, shapes, `Divider`) sit inside legacy containers, which is
  allowed. Consequences the port must respect: `Row`/`Column` gap is 0 where
  `HStack`/`VStack` default to 8 (divergence 52, so every SwiftCrossUI
  `HStack {}` without `spacing:` becomes `Row(gap: Pixels(8))`), and the
  legacy modifier order rule (container/item modifiers before `.padding`;
  `.frame`/background/corner radius after).
- **Severity.** High — it decides the vocabulary of the entire port and makes
  a SwiftUI → MetalUI port a rewrite of every container rather than a rename.

## MG-2 — no `@Environment(Type.self)` / `.environment(object)`

- **What.** `Environment` has only `init(_ keyPath:)`
  (`EnvironmentProperty.swift:68`); SwiftUI's object form,
  `@Environment(EditorState.self)` with `.environment(editor)`, is absent.
  Custom `EnvironmentKey`s exist, but a key's `defaultValue` must be
  producible without the app's one main-actor model instance, so it can only
  be an optional.
- **Where.** All 20 view types read `@Environment(EditorState.self) var
  editor`; `App.swift:11` installs it.
- **Workaround.** Each `Component` stores `let editor: EditorState`, passed
  down from `ContentView` (one model per process, so nothing is lost). An
  `EnvironmentKey` of type `EditorState?` was rejected: every reader would
  unwrap.
- **Severity.** Medium — mechanical, but it threads a parameter through every
  pane and leaf (`KeyCapView`, `PaletteChip`, …).

## MG-3 — no window toolbar API

- **What.** No `.toolbar`, `ToolbarItem`, or unified title-bar/toolbar window
  style; `App.openWindow` takes a title and sizes only.
- **Where.** `Views/TitlebarView.swift` — six icon buttons (New, Open, Save,
  Save As, Import, Export) and the Advanced Mode switch, drawn as a 50-point
  content strip under the traffic lights to look like a toolbar.
- **Workaround.** Per the user's decision the fake titlebar is deleted: the
  six actions move to the menu bar (`App.commands`, a File menu with ⌘N, ⌘O,
  ⌘S, ⇧⌘S, Import…, Export…) and Advanced Mode becomes a checked View-menu
  item. The six toolbar icon PNGs stay bundled (`AppIcon` keeps its cases, so
  `IconLoaderTests` keeps its contract) but nothing draws them.
- **Severity.** Medium — the file actions lose their one-click icons.

## MG-4 — `Toggle` has only the checkbox look

- **What.** `.toggleStyle`, `.switch` and `ToggleStyle` are not offered
  (`Toggle.swift:13`, divergences "Not offered").
- **Where.** The Advanced Mode switch (`TitlebarView.swift:67`, now a menu
  item, MG-3) and the macro library's ON switch
  (`MacroLibraryRowView.swift:82`).
- **Workaround.** The checkbox. `DesignModeViews.swift:65` and
  `DesignGridEditorView.swift:88` were a checkbox and the platform default
  already.
- **Severity.** Low.

## MG-5 — file dialogs take no starting directory and no title

- **What.** `FileDialogs.openFiles(allowedContentTypes:allowsMultipleSelection:)`,
  `saveFile(contentTypes:defaultFilename:)` and `.fileImporter`/
  `.fileExporter` have no `initialDirectory`/`fileDialogDefaultDirectory`
  (listed "not built" in `divergences.md`) and no title/message.
- **Where.** Open and Save As start in `~/esp/SMK` and are titled "Open
  keymap.json"/"Save keymap.json" (`TitlebarView.swift:21-24`, `82-86`);
  every other dialog has a title ("Import theme JSON", "Export macro", …).
- **Workaround.** The panel opens where AppKit last left it; `contentTypes:
  [.json]` and `defaultFilename:` carry what they can.
- **Severity.** Low.

## MG-6 — colour emoji are not drawn

- **What.** Colour glyphs are a renderer constraint (`divergences.md`, "Not
  offered": "gradients, SF Symbols, colour glyphs").
- **Where.** The trash glyph "🗑" on a hovered layer row
  (`KeyModeViews.swift:61`) and on every macro library row
  (`MacroLibraryRowView.swift:95`).
- **Workaround.** A monochrome glyph in `Chrome.dangerText` ("✕"), keeping
  the tooltip "Delete this macro". (The other glyphs — ⧉ ↑ ▲ ▼ ✕ ⋮⋮ → – × —
  are monochrome; whether CoreText fallback finds each one is checked in the
  lane that ports it and appended here if not.)
- **Severity.** Low.

## MG-7 — no colour picker

- **What.** No `ColorPicker`.
- **Where.** THM colour roles (`ThemeSwatchField.swift`); SwiftCrossUI had
  none either, which is why hex fields exist.
- **Workaround.** Unchanged: a swatch plus a `#RRGGBB` `TextField`.
- **Severity.** Low.

## MG-8 — a menu `Picker` has no sections

- **What.** `Section` is not offered in menus or a `.menu` picker
  (`divergences.md`, "Not offered").
- **Where.** The keystroke step's key chooser over `KeyName`'s several hundred
  cases (`MacroInspectorView.swift:613-655`), which today groups chips by
  `KeyName.allGroups`.
- **Workaround.** `.pickerStyle(.menu)` over every key with the group title in
  each option's title ("Letters — A") — the user's port note allows a menu
  picker here. The KEY-mode palette keeps its grouped chip sections.
- **Severity.** Low.

## MG-9 — no materials

- **What.** No backdrop blur / `Material` (`divergences.md`, "Not offered":
  materials).
- **Where.** The rail's "glass" tiles (`UIStyle.swift:31-39`).
- **Workaround.** Unchanged: translucent palette colours (`glassFill`,
  `glassActiveFill`).
- **Severity.** Low.

## MG-10 — no bundle image initialiser, no template tinting

- **What.** `Image` takes an `ImageBitmap`; there is no `Image(_ name:,
  bundle:)`, no `Image(url)`, and no `.renderingMode(.template)`/tint.
  `ImageBitmap(contentsOfFile:)` decodes through ImageIO on every call.
- **Where.** The rail icons (`UIStyle.swift:228-238`), picked per colour scheme
  (`AppIcon.swift:46-54`).
- **Workaround.** `IconLoader` keeps resolving `Bundle.module` URLs; a small
  `@MainActor` cache decodes each `(icon, scheme)` PNG once into an
  `ImageBitmap`. Icons stay pre-tinted light/dark PNGs, chosen with
  `@Environment(\.colorScheme)`.
- **Severity.** Low.
