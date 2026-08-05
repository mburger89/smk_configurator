# Dark Mode Support

Date: 2026-08-04
Status: Approved, pending implementation plan

## Problem

The app's entire visual chrome — titlebar, icon rail, status bar, list/inspector columns, buttons, dots, dividers — is defined by a single `Chrome` enum of hardcoded light-mode `Color` constants in `Sources/SMKConfigurator/Views/UIStyle.swift`, referenced ~100 times across 13 view files. There is no dark mode: the app looks the same regardless of the system appearance.

SwiftCrossUI (the UI framework this app is built on, via `DefaultBackend`/`AppKitBackend`) already has first-class support for this that the app isn't using yet:
- `@Environment(\.colorScheme)` tracks the live macOS system appearance, including runtime changes (the AppKit backend observes `AppleInterfaceThemeChangedNotification` and updates the whole environment tree automatically).
- `.preferredColorScheme(_:)` lets a window override that system value per-subtree (`nil` defers back to the system).

Goal: make every view dark-mode aware, following the system by default, with an in-app override (Light/Dark/System) that persists across launches.

## Design overview

Four pieces:

1. **`AppearanceMode`** — a new enum (`.light`/`.dark`/`.system`), persisted on `EditorState` the same way `drawerHeight`/`showAdvanced` already are (plain `UserDefaults`, no new persistence mechanism).
2. **App-level wiring** — `App.swift` applies `.preferredColorScheme(editor.appearanceMode.colorScheme)` to the root view, and adds a `View ▸ Appearance` menu (Light/Dark/System, checkable) via SwiftCrossUI's `.commands` scene modifier.
3. **`Chrome` refactor** — from a `static let` enum to a `struct` constructed from a `ColorScheme`, with every token becoming a light/dark computed pair.
4. **Per-view wiring** — every view struct touching `Chrome` reads `@Environment(\.colorScheme)` and derives a local `chrome` instance from it; all `Chrome.foo` call sites become `chrome.foo`.

## 1. `AppearanceMode`

Added to `Sources/SMKConfigurator/Model/EditorState.swift`, next to the existing `RailMode` enum:

```swift
enum AppearanceMode: String, CaseIterable, Identifiable {
    case light, dark, system
    var id: String { rawValue }

    /// `nil` means "defer to the OS", passed straight to `.preferredColorScheme`.
    var colorScheme: ColorScheme? {
        switch self {
            case .light: .light
            case .dark: .dark
            case .system: nil
        }
    }
}
```

`EditorState` gets:
```swift
var appearanceMode: AppearanceMode
```
initialized in `init()` from `UserDefaults.standard.string(forKey: appearanceModeDefaultsKey)` (falling back to `.system` if unset or unrecognized — same `private let ...DefaultsKey` pattern as `drawerHeightDefaultsKey`), and a mutator:
```swift
func setAppearanceMode(_ mode: AppearanceMode) {
    appearanceMode = mode
    UserDefaults.standard.set(mode.rawValue, forKey: appearanceModeDefaultsKey)
}
```
Default (fresh install / no stored value): `.system`.

## 2. App-level wiring

`Sources/SMKConfigurator/App.swift`:

```swift
@main
struct SMKConfiguratorApp: App {
    @State var editor = EditorState()

    var body: some Scene {
        WindowGroup("SMK Keymap Configurator") {
            ContentView()
                .environment(editor)
                .preferredColorScheme(editor.appearanceMode.colorScheme)
        }
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandMenu("View") {
                Menu("Appearance") {
                    ForEach(AppearanceMode.allCases) { mode in
                        Toggle(
                            mode.rawValue.capitalized,
                            isOn: Binding(
                                get: { editor.appearanceMode == mode },
                                set: { isOn in if isOn { editor.setAppearanceMode(mode) } }
                            )
                        )
                    }
                }
            }
        }
    }
}
```

SwiftCrossUI merges any `CommandMenu("View")` into the platform's real, already-present View menu (confirmed in `AppKitBackend+MenuBar.swift`: menus named `File`/`Edit`/`View`/`Window`/`Help` have their items appended to the native menu of the same name rather than creating a duplicate). There's no supported hook into the app's own named menu (that one's hardcoded to About/Services/Quit by the backend), so `View ▸ Appearance ▸ Light/Dark/System` is the closest native fit. Each `Toggle` shows a checkmark when its mode is active; selecting a different one flips `editor.appearanceMode`, which re-renders the checkmarks and (via `.preferredColorScheme`) the whole app.

## 3. `Chrome` refactor

`Sources/SMKConfigurator/Views/UIStyle.swift`: `Chrome` changes from an `enum` of `static let` to a `struct` holding the active `ColorScheme`, with every token a computed `var` branching light/dark:

```swift
struct Chrome {
    var scheme: ColorScheme

    var bar: Color { scheme == .dark ? .hex("#2B2B2D") : .hex("#F6F6F7") }
    var canvas: Color { scheme == .dark ? .hex("#1E1E20") : .hex("#ECECEE") }
    var column: Color { scheme == .dark ? .hex("#252527") : .hex("#FBFBFC") }
    var divider: Color { scheme == .dark ? .hex("#3A3A3C") : .hex("#E3E3E5") }
    var dividerLight: Color { scheme == .dark ? .hex("#333335") : .hex("#DDDDDD") }
    var surface: Color { scheme == .dark ? .hex("#2C2C2E") : .white }

    var accent: Color { scheme == .dark ? .hex("#0A84FF") : .hex("#007AFF") }
    var accentWash: Color { accent.opacity(scheme == .dark ? 0.18 : 0.12) }

    var textPrimary: Color { (scheme == .dark ? Color.white : .black).opacity(0.85) }
    var textSecondary: Color { (scheme == .dark ? Color.white : .black).opacity(0.6) }
    var textTertiary: Color { (scheme == .dark ? Color.white : .black).opacity(0.45) }

    var pillBackground: Color { scheme == .dark ? .hex("#3A3A3C") : .hex("#ECEEF0") }
    var chipBackground: Color { scheme == .dark ? .hex("#323234") : .hex("#F2F2F4") }
    var chipBorder: Color { scheme == .dark ? .hex("#48484A") : .hex("#E0E0E2") }

    var railActiveBackground: Color { accent }
    var railInactiveBackground: Color { pillBackground }

    var toggleOn: Color { scheme == .dark ? .hex("#30D158") : .hex("#34C759") }
    var toggleOff: Color { scheme == .dark ? .hex("#48484A") : .hex("#E2E2E5") }

    var dangerText: Color { scheme == .dark ? .hex("#FF453A") : .hex("#D92C2C") }
    var connectedDot: Color { toggleOn }
    var disconnectedDot: Color { scheme == .dark ? .hex("#6E6E73") : .hex("#B0B0B4") }
}
```

(`railActiveBackground`/`railInactiveBackground`/`connectedDot` already duplicated other tokens' values in the light palette — kept as aliases rather than re-deriving, same as today.)

Color mapping (light unchanged from today; dark new):

| token | light | dark |
|---|---|---|
| bar | #F6F6F7 | #2B2B2D |
| canvas | #ECECEE | #1E1E20 |
| column | #FBFBFC | #252527 |
| divider | #E3E3E5 | #3A3A3C |
| dividerLight | #DDDDDD | #333335 |
| surface | white | #2C2C2E |
| accent | #007AFF | #0A84FF |
| accentWash | accent @ 12% | accent @ 18% |
| textPrimary/Secondary/Tertiary | black @ 85/60/45% | white @ 85/60/45% |
| pillBackground / railInactiveBackground | #ECEEF0 | #3A3A3C |
| chipBackground | #F2F2F4 | #323234 |
| chipBorder | #E0E0E2 | #48484A |
| toggleOn / connectedDot | #34C759 | #30D158 |
| toggleOff | #E2E2E5 | #48484A |
| dangerText | #D92C2C | #FF453A |
| disconnectedDot | #B0B0B4 | #6E6E73 |

`accent`/`toggleOn`/`dangerText` pairs are Apple's standard HIG dynamic system-blue/green/red pairs; the rest are custom-derived to keep the existing light palette's contrast relationships in dark form.

`Color.hex(_:opacity:)` (the existing parsing helper, unchanged) and the `Chrome` enum's static-namespace usage (`Chrome.bar`, etc.) both go away — `Chrome` becomes something you construct, not a namespace.

## 4. Per-view wiring

Every `View` struct that references `Chrome` (23 structs across `UIStyle.swift`, `ContentView.swift`, `DesignCellView.swift`, `DesignGridEditorView.swift`, `DesignModeViews.swift`, `DeviceModeViews.swift`, `IconRailView.swift`, `KeyCapView.swift`, `KeyModeViews.swift`, `PaletteDrawerView.swift`, `StatusBarView.swift`, `ThemeModeViews.swift`, `ThemeSwatchField.swift`, `TitlebarView.swift`) gets two added lines:

```swift
@Environment(\.colorScheme) private var colorScheme
private var chrome: Chrome { Chrome(scheme: colorScheme) }
```

and every `Chrome.foo` reference in that struct's body becomes `chrome.foo` (mechanical rename, token names unchanged). No protocol/shared-default abstraction for the two boilerplate lines — 23 occurrences of two short lines doesn't justify one, and each struct's `@Environment` property must be a real stored property (property wrappers can't be injected via a protocol extension).

`Chrome`'s own internal helper views in `UIStyle.swift` (`SectionHeader`, `TapTarget`, `ToolbarPill`, `RailButton`, `InspectorButton`, `StatusDot`) get the same treatment — they're `View` structs like any other.

## Testing

- `swift build` — compiles clean (this refactor touches every file that currently imports `Chrome`; a single missed `Chrome.foo` → `chrome.foo` rename is a compile error, not a silent bug, since `Chrome` stops existing as a static namespace).
- `swift run`, manually:
  - Confirm the app matches the current macOS system appearance on launch with `Appearance` left at the default (System).
  - Toggle macOS System Settings ▸ Appearance while the app is running and on "System" — confirm the app's colors flip live, matching the window titlebar/menu bar (which SwiftCrossUI already themes automatically).
  - Use `View ▸ Appearance` to force Light, then Dark, then System — confirm each takes effect immediately and the checkmark tracks the active selection.
  - Quit and relaunch with Dark forced — confirm it's remembered (persisted via `UserDefaults`, read back into `EditorState.init()`).
  - Spot-check all four rail panes (Key/Designs/Themes/Device) plus the palette drawer in both light and dark for legibility (text contrast, border visibility) — this is a full re-skin of every custom-drawn surface in the app, not just a top-level flag flip, so it needs an eyes-on pass across panes rather than a single screenshot.
