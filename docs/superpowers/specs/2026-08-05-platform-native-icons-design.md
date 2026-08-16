# Platform-Native Icons

Date: 2026-08-05
Status: Approved, pending implementation plan

## Problem

The app's icon rail (`KEY`/`DSN`/`THM`/`DEV`) and titlebar toolbar (`New`/`Open`/`Save`/`Save As`/`Import`/`Export`) are plain text labels today (`RailButton`/`ToolbarPill` in `Sources/SMKConfigurator/Views/UIStyle.swift`). The goal is to make these feel native on whichever OS the app is running on — SF Symbols on macOS, Fluent System Icons on Windows, Adwaita/freedesktop-style icons on Linux — the way a first-party app on each platform would look.

SwiftCrossUI has no hook for this out of the box. Its `Image` view (`Views/Image.swift` in the vendored `swift-cross-ui` package) only accepts a file `URL` (PNG/JPG/WebP — no SVG) or raw RGBA pixel data, has no tinting/template-rendering mode, and exposes no way to call a live OS symbol API (`NSImage(systemSymbolName:)`, Fluent's glyph font, or GTK's icon-theme lookup) through the cross-platform API surface — that would require backend-specific bridge code the framework doesn't expose. So "native" here means *visually native* (the real icon shapes each platform's users recognize), not *dynamically native* (auto-tracking the user's installed icon theme or accent color at runtime).

## Design overview

Four pieces:

1. **Icon generation script** — a one-time (re-runnable) script that produces pre-rendered, pre-tinted PNGs from each platform's real icon set.
2. **Bundled resources** — the generated PNGs, checked into the repo and declared as a SwiftPM `resources:` bundle.
3. **`AppIcon`/`IconLoader`** — a small Swift helper that picks the right platform folder (compile-time `#if os(...)`) and color-scheme folder (runtime `@Environment(\.colorScheme)`, reusing the `ColorScheme` machinery from the dark-mode work) and returns a `URL` for SwiftCrossUI's `Image(_:)`.
4. **`RailButton`/`ToolbarPill` icon-only variants** — both switch from text-only to icon-only with `.help(_:)` tooltips.

## 1. Icon generation script

New files: `Scripts/generate-icons.sh` (orchestrator) and `Scripts/RenderSFSymbol.swift` (a `swiftc`-run helper for the AppKit part, not part of the app target — a standalone script invoked by the shell script, not built by `Package.swift`).

Ten icon concepts, each rendered twice per platform (light/dark tint) at the sizes the two call sites need (rail: ~22pt within a 40×40 frame; toolbar: ~16pt within the existing pill padding):

| App icon | Concept | SF Symbol (macOS) |
|---|---|---|
| `key` | keyboard | `keyboard` |
| `designs` | grid/layout | `square.grid.3x3` |
| `themes` | color/palette | `paintpalette` |
| `device` | device/connection | `cable.connector` |
| `newDoc` | new document | `doc.badge.plus` |
| `open` | open folder | `folder` |
| `save` | save | `square.and.arrow.down` |
| `saveAs` | save a copy | `doc.on.doc` |
| `importFile` | import | `tray.and.arrow.down` |
| `exportFile` | export | `tray.and.arrow.up` |

**macOS (SF Symbols):** `RenderSFSymbol.swift` uses `NSImage(systemSymbolName:accessibilityDescription:)` + `NSImage.SymbolConfiguration(pointSize:weight:)`, draws into an `NSBitmapImageRep` tinted with the target color (`chrome.textPrimary`'s light/dark values — `.black` @ 85% / `.white` @ 85%, matching every other icon-like glyph in the app), and writes a PNG. Run once per `(symbol name, size, tint)` tuple from the shell script. This only ever ships inside the macOS build, which keeps it within Apple's SF Symbols license (bundling into apps built for Apple platforms).

**Windows (Fluent System Icons):** the shell script fetches each icon's SVG from Microsoft's [`fluentui-system-icons`](https://github.com/microsoft/fluentui-system-icons) repo (MIT-licensed; the "regular" 24px style is the closest visual match to SF Symbols' default weight) via `curl`, then rasterizes with `rsvg-convert -w <size> -h <size> --stylesheet <tint-css>` into light/dark PNGs. Exact source filenames (Microsoft's naming is `ic_fluent_{name}_{size}_{style}.svg`) get resolved against the repo's real directory listing during implementation — not guessed here.

**Linux (Adwaita):** same `curl` + `rsvg-convert` treatment, sourced from GNOME's Adwaita icon theme repo (symbolic icons, which are single-color by design — the format this app needs anyway). Exact icon names (freedesktop icon-naming-spec, e.g. `input-keyboard-symbolic`) likewise get resolved against the repo's real contents during implementation.

Output: `Sources/SMKConfigurator/Resources/Icons/{macOS,Windows,Linux}/{light,dark}/{icon}.png` — 3 platforms × 2 schemes × 10 icons = 60 files.

## 2. Bundled resources

`Package.swift`'s `SMKConfigurator` executable target gains:

```swift
resources: [
    .copy("Resources/Icons")
]
```

All three platforms' icon folders ship in every build (the unused ones cost a negligible number of small PNGs) — simpler than conditionally excluding two of the three platform folders per build, and it means any platform's icons can be spot-checked from any dev machine by pointing `IconLoader` at a different folder temporarily.

## 3. `AppIcon` / `IconLoader`

New file: `Sources/SMKConfigurator/Views/AppIcon.swift`

```swift
enum AppIcon: String {
    case key, designs, themes, device
    case newDoc, open, save, saveAs, importFile, exportFile
}

enum IconLoader {
    static func url(for icon: AppIcon, colorScheme: ColorScheme) -> URL? {
        let platformDir: String
        #if os(macOS)
        platformDir = "macOS"
        #elseif os(Windows)
        platformDir = "Windows"
        #else
        platformDir = "Linux"
        #endif
        let schemeDir = colorScheme == .dark ? "dark" : "light"
        return Bundle.module.url(
            forResource: icon.rawValue,
            withExtension: "png",
            subdirectory: "Icons/\(platformDir)/\(schemeDir)"
        )
    }
}
```

## 4. `RailButton` / `ToolbarPill` icon-only variants

Both are defined in `Sources/SMKConfigurator/Views/UIStyle.swift` and already read `@Environment(\.colorScheme)` (added in the dark-mode work), so `IconLoader.url(for:colorScheme:)` slots straight in.

`RailButton` changes from a `label: String` to an `icon: AppIcon` + `tooltip: String` (the tooltip carries what the text label used to — "Keymap", "Designs", "Themes", "Device" — since `KEY`/`DSN`/`THM`/`DEV` were already abbreviations, not full words):

```swift
struct RailButton: View {
    var icon: AppIcon
    var tooltip: String
    var isActive: Bool
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var chrome: Chrome { Chrome(scheme: colorScheme) }

    var body: some View {
        TapTarget(
            background: isActive ? chrome.railActiveBackground : chrome.railInactiveBackground,
            cornerRadius: 9,
            action: action
        ) {
            if let url = IconLoader.url(for: icon, colorScheme: colorScheme) {
                Image(url).resizable().frame(width: 20, height: 20)
            }
        }
        .frame(width: 40, height: 40)
        .help(tooltip)
    }
}
```

`ToolbarPill` follows the same shape: `label: String` (used for the tooltip and unchanged as the call sites' parameter name) + `icon: AppIcon`, rendering the icon in place of `Text(label)` inside the pill, with `.help(label)` added.

`IconRailView` and `TitlebarView` (the two call sites) update their `RailButton(label: "KEY", ...)` / `ToolbarPill(label: "New", ...)` construction calls to pass an `icon:` argument alongside.

## Testing

- `swift build` on macOS — compiles clean, `Bundle.module` resolves the new resource bundle.
- `swift run` on macOS, manually: confirm all 4 rail icons and 6 toolbar icons render the correct SF Symbol shapes, correctly tinted in both Light and Dark (View ▸ Appearance, reusing the dark-mode work's menu), and that hovering each shows the right tooltip.
- Windows/Linux: compile-verified only, via the existing CI workflows (`.github/workflows/*.yml`) that already build the whole package on those platforms — proves the `resources:` bundle and `#if os(...)` branches build, not that the icons render correctly. No way to visually verify from this machine, same limitation as the rest of this app's non-macOS work (called out identically in the hidapi USB transport spec).
