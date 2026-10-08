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
written. Later lanes appended MG-11…MG-22. MG-23 onward come from the Linux/Windows item
(`2026-10-08-metalui-cross-platform-plan.md`), against MetalUI `70ed000`.

**Ordered by severity** (high, medium, low; within a band, the entry an app
meets first comes first), not by id, so the last heading is not the newest
entry. **Next unused id: MG-28.** A new entry takes it, goes into its band and
the table below, and moves this line.

| severity | entries |
|---|---|
| high | MG-1, MG-15 |
| medium | MG-20, MG-17, MG-14, MG-2, MG-3, MG-23, MG-24, MG-27 |
| low | MG-4, MG-5, MG-6, MG-7, MG-8, MG-9, MG-10, MG-11, MG-12, MG-13, MG-16, MG-18, MG-19, MG-21, MG-22, MG-25, MG-26 |

---

# High

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

# Medium

## MG-20 — `TextField`/`TextEditor` draw no field chrome, and there is no `.textFieldStyle`

- **What.** MetalUI's `TextField` and `TextEditor` paint the text, caret and
  selection only — no bezel, background or border — and `.textFieldStyle`
  (`.roundedBorder`, `.plain`) is not offered. SwiftUI's macOS default is a
  rounded-border field. Not listed in `docs/divergences.md`. Seen at the
  lane-3 launch: the library's "Search macros" and each row's "Collection"
  field read as loose placeholder text, the text step's editor as a floating
  line.
- **Where.** Every field: the library search and collection fields, the macro
  name, the text step's `TextEditor`, the DSN name field, the THM hex fields.
- **Workaround.** An app helper, `StyledElement.fieldChrome()`
  (`Views/UIStyle.swift`): 6/3 padding, `Chrome.surface`, radius 5, a 1-point
  `Chrome.chipBorder`, written before `.frame`. Applied to all six fields
  (lane 3's parity pass also applied it to lane 2's DSN and THM fields).
- **Severity.** Medium — every app with a form writes this, and without it a
  field is not recognisable as one.
- **Status at `70ed000`.** Fixed upstream: `TextField` draws SwiftUI's
  bordered field by default and `.textFieldStyle(_:)`/`.textEditorStyle(_:)`
  exist (MetalUI `MD-B`, `MD-C`, `MD-F`). Adopted by cross-platform lane 1,
  because the old helper on top of the new default drew two borders: the five
  `TextField`s drop the helper and keep MetalUI's chrome (`.surface` fill,
  `.separator` border, radius 6, the control focus ring); the one `TextEditor`
  keeps the app's chrome, renamed `editorChrome()`, over
  `.textEditorStyle(.plain)`, since MetalUI's editor default is a fill with no
  border and no text inset (its divergence 133).

## MG-17 — no public input injection for an app's tests

- **What.** `Window` has no public way to deliver an `InputEvent` (a click, a
  drag, a drop) from a test; `onInput` is a hook, and `InputEvent` dispatch is
  internal. An app cannot test "drag this chip onto that key" end to end.
- **Where.** The KEY board's drop destinations and the palette chips' drags
  (`Views/KeyCapView.swift`, `Views/PaletteDrawerView.swift`); lane 3: the
  ADD STEP rows' drags onto the "Add a step" card (`MacroStepTypeRow`,
  `ContentView.addStepCard`), and every click in the macro panes.
- **Workaround.** The drop logic is a plain function (`PaletteDrop`; lane 3's
  `MacroStepDrop`), tested with the model's `assign`/`appendStep`
  (`PaneLogicTests`, `MacroPaneLogicTests`); the gesture itself is
  unverified until someone drags a chip in the running app.
- **Severity.** Medium — every interaction an app adds is untestable below a
  human check.
- **Status at `70ed000` (cross-platform lane 2, 2026-10-08).** Still no
  injection API on `Window`, but an app can reach `onInput` through its own
  `Platform`: `App(platform:textSystem:)` takes any conformer, and
  `PlatformWindow.onInput` is the hook a platform calls. `PlatformChromeTests`
  writes a headless fake (`ChromeFakePlatform`/`ChromeFakeWindow`, all 28
  `PlatformWindow` members, a renderer that presents every frame and draws
  nothing) and drives a real click, a key press and toolbar actions through
  it, on all three platforms with no GPU. The cost is that fake (about 80
  lines) per test target, and it tracks `PlatformWindow`'s defaultless
  requirements, so a MetalUI bump that adds one breaks the app's test build.
  The macro panes' drags are still not driven this way.

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
- **Status at `70ed000`.** Fixed upstream: a legacy container sees through a
  `layoutPriority` layer (MetalUI `MD-G`). Not adopted; the workaround stays
  (follow-up work, cross-platform plan §6).

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
- **Status at `70ed000`.** Fixed upstream: `@Environment(Type.self)` reads an
  `@Observable` object provided by `.environment(_ object:)`, and a missing
  one traps (MetalUI `MD-H`, its divergence 134). Not adopted; `let editor`
  stays (follow-up work, cross-platform plan §6).

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
- **Status at `70ed000`.** Fixed upstream: `.toolbar`/`.searchable` over a
  closed item set, a native `NSToolbar` on AppKit, a drawn 39-point strip on
  SDL (MetalUI `MD-I`, `MD-J`, `MD-K`). Used on Linux and Windows only, for
  MG-23's workaround (cross-platform lane 2); macOS keeps the menu bar and no
  toolbar, the user's decision above.

## MG-23 — `App.commands` draws nothing on SDL: menu-only actions are unreachable on Linux and Windows

*Found by the cross-platform planning survey (2026-10-08, MetalUI `70ed000`).*

- **What.** `SDLPlatform.setMenuBar(_:)` records the menu bar and draws
  nothing (`Backends/SDL/Sources/MetalUISDL/SDLPlatform.swift:146-155`,
  MetalUI ruling `MN-I` item 3: "SDL3 has no menu-bar API … An in-window menu
  bar is deferred, owner none"). A command's keyboard shortcut still fires
  (the window's command stage, `MN-J`). A command **without** a shortcut has
  no way in, and neither do the standard AppKit items (Quit, Close, Edit).
  Minimal reproduction: `app.commands { CommandMenu("View") { Toggle("X",
  isOn: …) } }` under `App(platform: try SDLPlatform(), …)`. No menu appears
  and nothing toggles X.
- **Where.** `Views/AppCommands.swift`: File ▸ Import… and Export… have no
  shortcut, and neither do View ▸ Advanced Mode and View ▸ Appearance. New,
  Open, Save and Save As are reachable only by their shortcuts.
- **Workaround.** On Linux and Windows only, a `.toolbar` (MetalUI draws it
  as a 39-point strip where `setToolbar` answers `false`; divergence 136,
  `MD-K`) mirrors the File and View menus. The six file actions are icon
  buttons, Advanced Mode is a `Toggle` and Appearance a `.menu` `Picker`.
  One command table feeds both the menu and the toolbar (cross-platform
  plan §1.2 M1).
- **Severity.** Medium. Any app that puts actions only in its menu bar loses
  them on Linux and Windows without a word.
- **Workaround in place (cross-platform lane 2, 2026-10-08).**
  `Views/PlatformToolbar.swift`: `FileCommand.all` (title, `AppIcon`,
  shortcut, divider, action) feeds both the File menu (`installAppCommands`)
  and `fileToolbar`, which `ContentView` applies through `platformToolbar`
  (`#if os(macOS)` returns `self`). Pinned by `PlatformChromeTests`: the menu
  bar and toolbar a platform receives carry the table in order, and in a
  window whose platform answers `false` to `setToolbar` the drawn strip lays
  out the real shell and its New button runs New (Linux image and macOS).
  Quit and Close have no in-window item on SDL; the window's close button is
  the way out.

## MG-24 — a keyboard shortcut's default `.command` is the Super/Windows key on SDL; there is no "primary" modifier

*Found by the cross-platform planning survey (2026-10-08, MetalUI `70ed000`).*

- **What.** `KeyboardShortcut(_:modifiers:)` defaults to `.command`
  (`Sources/MetalUI/KeyboardShortcut.swift:79`), and modifiers match exactly
  (`IX-F` item 2). The SDL bridge maps `SDL_KMOD_GUI` to `.command` and
  `SDL_KMOD_CTRL` to `.control` (`Backends/SDL/Sources/SDLBridge/SDLBridge.c:798-800`).
  So `.keyboardShortcut("s")` on Linux and Windows fires on Super+S or Win+S,
  never Ctrl+S, and Windows itself takes Win+S (search), Win+N and Win+O. No
  modifier spelling means "⌘ on Apple, Ctrl elsewhere". MetalUI's own text
  editing does make that switch internally (`TextEditing.platform`, `TI-D`),
  so a field's Ctrl+C/V works while the app's Ctrl+S does not.
  Minimal reproduction: `Button("Save") { … }.keyboardShortcut("s")` in an
  SDL window. Ctrl+S does nothing.
- **Where.** Every shortcut in `Views/AppCommands.swift`: ⌘N, ⌘O, ⌘S, ⇧⌘S.
- **Workaround.** An app constant, `primaryShortcutModifier: EventModifiers`
  (`.command` under `#if os(macOS)`, `.control` otherwise), passed on every
  `.keyboardShortcut`.
- **Severity.** Medium. Every portable app writes this, and the default
  silently binds a key that Windows reserves.
- **Workaround in place (cross-platform lane 2, 2026-10-08).**
  `primaryShortcutModifier` in `Views/PlatformToolbar.swift`, on every entry
  of `FileCommand.all` (Save As is `[primary, .shift]`). Pinned by
  `PlatformChromeTests`: primary+N runs New through the window's command
  stage, and off macOS Super+N does not.

## MG-27 — Swift 6.4.0's Windows toolchain asserts on `-c release` in a `Component` whose `content` is a `switch` (toolchain, not MetalUI)

*Found by cross-platform lane 3 (2026-10-08, MetalUI `70ed000`, Swift 6.4.0
`swift-6.4-RELEASE` aarch64-unknown-windows-msvc on the UTM VM; the
toolchain installs as `Toolchains\6.4.0+Asserts`, i.e. with compiler
assertions on).*

- **What.** `swift build -c release` of the app on Windows ARM64 stops in
  SILGen with `Assertion failed: hasNoNontrivialLexicalLeaf && "Found
  non-trivial lexical leaf in non-trivial non-lexical type?!"`
  (`lib/SIL/IR/TypeLowering.cpp:3389`), exception `0xC000001D`, "While silgen
  visitDecl 'MacroStepEditor' (at Views/MacroInspectorView.swift:213:1)",
  "While generating protocol witness thunk … for 'prepaintGroup(layout:pass:)'
  (in module 'MetalUI')" -- the `ElementGroup` conformance of a `Component`
  whose `content` is a builder `switch` over six cases (one of them a
  `pane { }` type-erased recursive editor). The debug build of the same tree
  passes (and runs all 258 tests); the release build passes on macOS and in
  the Linux image (non-assertion toolchains). Adding
  `-Xswiftc -Xfrontend -Xswiftc -enable-lexical-lifetimes=false` does not
  avoid it. Not yet known for x64 (CI's architecture). This is very likely
  the "illegal instruction" crash the old Windows workflow retried around
  (`0xC000001D` is `STATUS_ILLEGAL_INSTRUCTION`, an assertion's trap), which
  a retry cannot fix when it is deterministic.
  Reproduction: this repository at the C4b lane 3 commit on Windows with
  Swift 6.4.0, the flags of `.github/workflows/windows-build.yml`, then
  `swift build -c release`. Not reduced further.
- **Where.** Only the Windows packaging (`Scripts/package-windows.ps1`) and
  the CI's Package step build release.
- **Workaround.** `package-windows.ps1 -Configuration debug` packages the
  debug build (8 MB main-thread stack from `/STACK`, which the debug build
  needs, gap MG-15). CI tries release first and falls back to debug with a
  warning, so the first x64 run says whether x64 shares it.
- **Severity.** Medium: a Windows release build is not possible on ARM64
  today, so a shipped Windows build would be a debug one. A Swift toolchain
  defect, not MetalUI's, but MetalUI's builder shape (a `switch` in an
  `ElementGroup` builder reaching `prepaintGroup`'s witness) is what meets it;
  worth reducing and filing upstream.

# Low

## MG-4 — `Toggle` has only the checkbox look

- **What.** `.toggleStyle`, `.switch` and `ToggleStyle` are not offered
  (`Toggle.swift:13`, divergences "Not offered").
- **Where.** The Advanced Mode switch (`TitlebarView.swift:67`, now a menu
  item, MG-3) and the macro library's ON switch
  (`MacroLibraryRowView.swift:82`).
- **Workaround.** The checkbox. `DesignModeViews.swift:65` and
  `DesignGridEditorView.swift:88` were a checkbox and the platform default
  already. *Lane 3, at launch:* the checked state is an accent-filled square
  with no check mark (MetalUI's documented one look, `Toggle.swift` header),
  so a column of ON checkboxes reads as filled/empty squares.
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

## MG-18 — no `.labelsHidden()`: a titleless `Picker`/`Stepper` keeps a leading gap and has no label

- **What.** `Picker` and `Stepper` always lay out `Text(title)`, 8, the
  control (`Picker.swift:113`, `Stepper.swift:94`); `.labelsHidden()` is not
  offered. An empty title leaves an 8-point leading inset and publishes an
  unlabelled control.
- **Where.** The KEY inspector's Key / Matrix / Theme segmented picker and the
  palette's layer-number stepper; lane 3: the macro inspector's Step / Macro /
  Timing picker, its Operation/Layer/Key pickers, the library's collection
  menu picker, and the library row's ON checkbox (`Toggle("")` keeps the
  7-point box-to-label gap after the box).
- **Workaround.** Title `""`; the stepper adds `.accessibilityLabel("Layer for
  MO and TG")`. The segmented picker stays unlabelled. Lane 3's titleless
  pickers and the ON checkbox each carry an `.accessibilityLabel`.
- **Severity.** Low.

## MG-19 — `.id(_:)` takes only a `String`

- **What.** Both spellings of the explicit-identity modifier take `String`
  (`ExplicitIdentity.swift:110`, `Box.swift:869`); SwiftUI's `.id(_:)` takes
  any `Hashable`. Minimal reproduction: `.id(row.id)` with an `Int` id fails
  with "cannot convert value of type 'Int' to expected argument type 'String'".
- **Where.** The macro library's rows (`Views/MacroLibraryView.swift`), keyed
  by macro id so a row's collection-field draft stays with its macro when the
  filter changes; the inspector's step editor, keyed by the selected index.
- **Workaround.** `.id("macro-\(row.id)")`, `.id("step-\(index)")`.
- **Severity.** Low.

## MG-21 — the segmented picker's look is two shared tokens; MetalUI's dark track is navy

- **What.** A segmented `Picker` paints its track `.surfaceSecondary` and the
  selected segment `.surface` (`Picker.swift:130`). `Theme.dark`'s
  `surfaceSecondary` is `#27304A`, a navy chosen against MetalUI's own dark
  surfaces. An app that retints `.surface` (here to the palette's grey
  `#2C2C2E`, port plan §3.4) gets a track that is *more* saturated than the
  selected segment, so in dark mode the **unselected** segments looked
  highlighted and the selected one plain. Seen at the lane-3 launch in the
  KEY inspector (Key selected, Matrix and Theme tinted) and the macro
  inspector; a capture with Timing selected confirmed the inversion.
- **Where.** Every segmented picker (KEY inspector tabs, macro inspector tabs,
  the layer step's Operation).
- **Workaround.** `ChromeTheme.apply(to:)` (`Views/Palette.swift`) also sets
  `app.darkTheme.surfaceSecondary = .rgb(0x1C1C1E)`, a track darker than
  `surface`, so the selected segment is the lighter one, as on macOS.
- **Severity.** Low, but silent: nothing ties the two tokens together, and
  the picker has no per-control colour.

## MG-22 — a recursive component needs type erasure, and `AnyElement` takes an `Element` only

- **What.** The step editor shows a repeat block's editor, which shows step
  editors for the steps inside it. `some ElementGroup` content cannot be
  recursive, so one side must be erased; `AnyElement` erases an `Element`, not
  an `ElementGroup` (a `Component`), so the erasure is
  `AnyElement(Box { … })`. SwiftUI's `AnyView` takes any view.
- **Where.** `MacroStepEditor` → `RepeatBlockEditor`
  (`Views/MacroInspectorView.swift`).
- **Workaround.** The app's `pane { }` helper (`AnyElement(Box(content:))`,
  `Views/KeyModeViews.swift`, introduced for MG-15) around the repeat-block
  editor.
- **Severity.** Low.

## MG-25 — the portable system fonts register no family for `.monospaced` (or serif, rounded)

*Found by the cross-platform planning survey (2026-10-08, MetalUI `70ed000`).*

- **What.** `SystemFonts.resolver()` (`Sources/MetalUISystemFonts/SystemFonts.swift`)
  registers default and fallback families only. It never calls
  `PortableFontResolver.register(design:family:)`, so on Linux and Windows a
  `.font(.system(size:weight:design: .monospaced))` resolves to the default
  sans face (an unregistered design "is the default face",
  `PortableFontResolver.swift:187-193`). CoreText gives SF Mono on macOS.
  Minimal reproduction: `Text("0x1F").font(.system(size: 12, design: .monospaced))`
  under `PortableTextSystem(resolver: try SystemFonts.resolver())`. It draws
  proportional DejaVu Sans or Segoe UI.
- **Where.** The eight `design: .monospaced` sites: the THM hex fields
  (`ThemeSwatchField`), the step rows and inspector byte counts
  (`MacroStepRowView`, `MacroInspectorView`, `MacroEditorViews`), and the KEY
  inspector's raw token (`KeyModeViews`).
- **Workaround.** `makeApp()` registers one family per platform after
  building the resolver: `"DejaVu Sans Mono"` on Linux, `"Consolas"` on
  Windows. A family that is not installed falls back to the default face, so
  nothing traps.
- **Severity.** Low. A one-line workaround, but the app must know a family
  name per platform.

## MG-26 — a MetalUI product filtered out of the app target on macOS breaks the test target's compile there (toolchain, not MetalUI)

*Found by cross-platform lane 1 (2026-10-08, MetalUI `70ed000`, Swift 6.4
`swiftlang-6.4.0.33.1`, the default build system).*

- **What.** With `.product(name: "MetalUIPortableText", package: "MetalUI",
  condition: .when(platforms: [.linux, .windows]))` (and the same for
  `MetalUISystemFonts`) on the executable target -- the shape
  `metalui new --cross-platform` generates -- while the test target names
  both products **unconditionally**, `swift build --build-tests` on macOS
  fails in the test target's dependency scan: `error: unable to resolve
  module dependency: 'CFreeType'` (and `'CHarfBuzz'`, `'CSheenBidi'`,
  `'CUnibreak'`). The test target's compile line carries
  `-fmodule-map-file` for `CStbImage` and `MetalUIShaderTypes` only. The plain
  `swift build` passes. Measured both ways: the two products conditional →
  fails; the same two unconditional (only `MetalUISDL` kept conditional) →
  passes. `--build-system native` not tried. The scaffold's own package has no
  test target, so MetalUI's scaffold build test cannot see this.
  Minimal reproduction: the scaffold's cross-platform manifest plus
  `.testTarget(name: "T", dependencies: ["App", .product(name:
  "MetalUIPortableText", package: "MetalUI")])` with one file
  `import MetalUIPortableText`, then `swift build --build-tests` on macOS.
- **Where.** `Package.swift`: the app's test target constructs
  `PortableTextSystem` on macOS for `renderFrame` (`ShellRenderTests`,
  `PaneRenderTests`, `MacroPaneTests`).
- **Workaround.** `MetalUIPortableText` and `MetalUISystemFonts` are
  unconditional dependencies of the executable target on every platform;
  macOS links them unused. Only `MetalUISDL` stays `condition: portable`.
- **Severity.** Low. A SwiftPM / swift-build defect rather than MetalUI's, but
  every consumer that follows getting-started's manifest and tests with the
  portable text system meets it; worth a line in MetalUI's getting-started or
  a test target in its scaffold build test.

---

**Final (lane 3, 2026-10-06).** MG-1…MG-22. None was fixed in MetalUI by this
branch. The ones an app meets first: MG-1 (legacy vocabulary for everything
with a control), MG-15 (debug-build stack overflow without type erasure),
MG-20 (fields with no chrome), MG-17 (no input injection for app tests),
MG-14 (no `layoutPriority` on legacy stacks). Launch-only findings (MG-20,
MG-21, MG-4's check mark) came from the first launch of the port, in lane 3;
lanes 1 and 2 ran with the screen locked.
