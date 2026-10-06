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

## MG-11 — no edge-set padding on legacy elements

- **What.** SwiftUI's `.padding(.horizontal, 16)`, `.padding(.top, 8)` and
  `.padding(EdgeInsets(…))` have no legacy spelling. A legacy element takes
  `.padding(Pixels)` or `.padding(Edges<Length>)` — CSS order (top, right,
  bottom, left), each edge wrapped as `.pixels(Pixels(n))`
  (`Sources/MetalUI/Box.swift:1152`, `:1177`); the proposal path takes
  `Edges<Pixels>` (`NativeModifiedContent.swift:88`). Neither has an
  `Edge.Set` form.
- **Where.** Every pane: the previous build wrote `EdgeInsets(top:bottom:
  leading:trailing:)` or `.padding(.horizontal, n)` at about 40 sites
  (status bar, macro editor column, list columns, rows).
- **Workaround.** An app helper, `Insets.edges(top:leading:bottom:trailing:)`
  and `Insets.symmetric(horizontal:vertical:)` (`Views/UIStyle.swift`),
  returning `Edges<Length>`.
- **Severity.** Low — a three-line helper, but every port writes it.

## MG-12 — a headless frame cannot select the dark scheme, run lifecycle, or report layout

*Rewritten in the lane-1 fix pass. The first version claimed an app cannot
build a frame headlessly at all; that was wrong. The `MetalUIPortableText` and
`MetalUISystemFonts` products give an app a `TextSystem`
(`PortableTextSystem(resolver: try SystemFonts.resolver())`), `GlyphAtlas` has
a public `init(width:height:)`, and the public `renderFrame(_:size:scaleFactor:
textSystem:atlas:theme:)` returns a `Scene`. `ShellRenderTests.everyModeRendersHeadlessly`
now renders every rail mode that way.*

- **What.** Three things the headless path does not cover:
  1. **No dark scheme.** `renderFrame`'s `theme:` sets the tokens only and
     leaves `colorScheme` light (MetalUI `Frame.swift:502`, `CR-K` item 3), so
     palette keys and `Color(light:dark:)` resolve light. The obvious
     workaround, `renderFrame({ rootView(…).environment(\.colorScheme, .dark) }, …)`,
     does not compile: `EnvironmentScope` is not an `Element`, and
     `renderFrame` takes `Root: Element`.
  2. **No lifecycle.** A headless `renderFrame` runs no
     `onAppear`/`onDisappear`/`onChange` (MetalUI CLAUDE.md, Lifecycle), so the
     DEV pane's monitor start or the load-error alert is unreachable there.
  3. **No layout read-back.** The result is a `Scene` (rects, glyphs, images
     in device pixels). There is no public read of a node's frame, so a test
     can assert "something drew" but not "the inspector is 248 wide".
- **Where.** `Tests/SMKConfiguratorTests/ShellRenderTests.swift`.
- **Workaround.** Two tests. `everyModeRendersHeadlessly` (no window, light
  only) asserts every rail mode yields rects and glyphs.
  `everyModeDraws` opens a real AppKit window with `startsDisplayLink: false`
  and calls the public `Window.drawFrameIfNeeded()` after each mode change, in
  every rail mode, both macro sub-states and both schemes (through
  `window.preferredColorScheme`), which runs the app's themes and the lifecycle
  drain. It works in a locked session. Both trap on a layout refusal; neither
  sees pixels or layout results.
- **Severity.** Low. App-level layout tests can only detect traps and empty
  output.

## MG-13 — `.help` reaches neither a `Component` nor an `EnvironmentScope`

- **What.** `.help(_:)` exists on `StyledElement` (returning `Self`) and on
  `ProposalElementGroup` (`Tooltip.swift:30`, `:42`), not on `ElementGroup`:
  a legacy `Component`, or anything after `.disabled(_:)`/`.font(_:)` (an
  `EnvironmentScope`), cannot take a tooltip from its caller.
- **Where.** The shared button styles (`PillButton` in `Views/UIStyle.swift`):
  "Record new" and "Test run" carry tooltips, and the style ends in
  `.disabled(!isEnabled)`.
- **Workaround.** The style takes `help: String?` and applies `.help` to the
  `Button` inside, before `.disabled`.
- **Severity.** Low.

## MG-14 — no `layoutPriority` on the legacy stacks

- **What.** `.layoutPriority(_:)` exists only on `ProposalElementGroup`
  (`NativeModifiedContent.swift:296`); a legacy `Column`/`Row` child cannot
  take one, and a proposal `VStack` cannot hold the palette drawer's `Button`s
  (MG-1). The legacy stacks divide space by SwiftUI's flexibility rule, so of
  a greedy board area and a 260…530 drawer the drawer is offered half of what
  is left, never "everything it wants first". Minimal reproduction:
  `Column(gap: Pixels(16)) { ScrollView(.vertical) { … }.frame(minHeight: Pixels(240), maxHeight: Pixels(.infinity)); drawer.frame(minHeight: Pixels(260), maxHeight: Pixels(530)) }`
  in an 800-tall slot offers the drawer (800 − 16) / 2 = 392, not 530 — derived
  from the stack rule (MetalUI `CN-B`), not measured: an app cannot read a
  laid-out frame back (MG-12).
- **Where.** KEY mode's main column (`Views/KeyModeViews.swift`,
  `KeyMainContentView`): the old build served the palette drawer first with
  `.layoutPriority(1)` so it reached its no-scroll maximum in a tall window.
- **Workaround.** The board's scroll area is capped at the board's own
  height (`KeyboardBoardView.naturalHeight(of:)`, at least
  `WindowMetrics.boardMinHeight`), so it is the less flexible child and is
  served first; the drawer then gets the rest up to its maximum. At the
  window's minimum height the board area works out at about 258 and the drawer
  at its 260 floor (a couple of points into the column's padding; derived, not
  measured); in a window
  taller than both maxima the leftover space sits below the drawer instead of
  growing the board.
- **Severity.** Medium — the drawer's height now depends on the design's row
  count, and an exact "serve this first" is not expressible.

## MG-15 — a `Component`'s layout record holds its whole content type: a large app overflows the stack in debug

- **What.** `ComponentLayout<C>` stores `C.Content` and
  `C.Content.GroupLayout` inline (`Component.swift`), and a `switch` in a
  builder keeps every branch's type. So a shell `Component` that switches
  between pane `Component`s carries the full static layout type of **every**
  pane of **every** mode at once, and the debug build's generic frames for it
  grow with the sum. With lane 2's four real panes in place, building the
  window root (`rootView(editor:)`) crashed with `EXC_BAD_ACCESS` in
  `___chkstk_darwin` on an 8 MB main-thread stack — in every rail mode,
  including MACROS, whose own panes were still one-line placeholders — while
  each pane rendered alone, and the three KEY panes side by side, without
  trouble. Reproduction: this branch's `ContentView` with the twelve pane
  `content`s not wrapped in `pane { }` (`Views/KeyModeViews.swift`), then
  `swift test --filter ShellRenderTests` (signal 11) or
  `renderFrame({ rootView(editor: editor) }, …)` in any mode.
- **Where.** `Views/ContentView.swift`'s list/main/inspector `switch`es over
  the KEY, DSN, THM, DEV and MACROS panes.
- **Workaround.** Every pane wraps its content in `pane { … }`
  (`AnyElement(Box { … })`), erasing its type at the pane boundary. The suite
  then passes; the app's real main thread has the same 8 MB.
- **Severity.** High — nothing warns until a debug build crashes, the crash
  is far from the code that grew, and the fix (type erasure at boundaries) is
  undocumented. MetalUI's own "Windows threads have 1 MB stacks" rule is the
  same hazard seen from the demo side; an app on the later Windows backend will
  meet it sooner.

## MG-16 — a `some Element` call inside a builder `for` loop does not compile

- **What.** In an `@ElementBuilder` body, a `for` loop whose body calls a
  function returning `some Element` (or `some ElementGroup`) fails with
  `error: underlying type for opaque result type 'some Element' could not be
  inferred from return expression`, pointing at the `for`. The same call
  outside a loop compiles, and a concrete type or a `Component` inside the loop
  compiles. Minimal reproduction (Swift 6.4, `swiftlang-6.4.0.33.1`):
  ```swift
  @MainActor func cell(_ i: Int) -> some Element { Text("\(i)") }
  struct Repro: Component {
      var items = [1, 2, 3]
      var content: some ElementGroup { Column { for i in items { cell(i) } } }
  }
  ```
  Possibly the compiler's `for`-in-builder transform rather than MetalUI's
  `buildArray`; not isolated further.
- **Where.** The palette drawer's sections, the KEY inspector's theme rows,
  the layer rows.
- **Workaround.** The loop bodies are small `Component`s (`PaletteSection`,
  `ThemeSwatchRow`, `LayerRow`) instead of private helpers returning opaque
  types.
- **Severity.** Low — easy once known, but the diagnostic names neither the
  loop body nor the cause.

## MG-17 — no public input injection for an app's tests

- **What.** `Window` has no public way to deliver an `InputEvent` (a click, a
  drag, a drop) from a test; `onInput` is a hook, and `InputEvent` dispatch is
  internal. An app cannot test "drag this chip onto that key" end to end.
- **Where.** The KEY board's drop destinations and the palette chips' drags
  (`Views/KeyCapView.swift`, `Views/PaletteDrawerView.swift`).
- **Workaround.** The drop logic is a plain function (`PaletteDrop`), tested
  with the model's `assign` (`PaneLogicTests`); the gesture itself is
  unverified until someone drags a chip in the running app.
- **Severity.** Medium — every interaction an app adds is untestable below a
  human check.

## MG-18 — no `.labelsHidden()`: a titleless `Picker`/`Stepper` keeps a leading gap and has no label

- **What.** `Picker` and `Stepper` always lay out `Text(title)`, 8, the
  control (`Picker.swift:113`, `Stepper.swift:94`); `.labelsHidden()` is not
  offered. An empty title leaves an 8-point leading inset and publishes an
  unlabelled control.
- **Where.** The KEY inspector's Key / Matrix / Theme segmented picker and the
  palette's layer-number stepper.
- **Workaround.** Title `""`; the stepper adds `.accessibilityLabel("Layer for
  MO and TG")`. The segmented picker stays unlabelled.
- **Severity.** Low.
