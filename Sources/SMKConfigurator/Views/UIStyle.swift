import SwiftCrossUI

/// Design tokens for the "Power / Grouped List" redesign (see
/// `design_handoff_1c_power_grouped_list/README.md`, section "Design
/// Tokens") -- centralized here so every pane pulls from the same palette
/// instead of re-deriving hex values.
struct Chrome {
    var scheme: ColorScheme

    /// Titlebar / icon rail / status bar background.
    var bar: Color { scheme == .dark ? .hex("#2B2B2D") : .hex("#F6F6F7") }
    /// Main content canvas background.
    var canvas: Color { scheme == .dark ? .hex("#1E1E20") : .hex("#ECECEE") }
    /// List / inspector column background.
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

    /// Faux-glass tile fill for icon-only buttons (`GlassIconTile`) --
    /// translucent rather than opaque like `pillBackground`, since a real
    /// backdrop-blur material isn't available (see `GlassIconTile`'s doc
    /// comment). Light mode needs a higher alpha than dark to stay visible
    /// against `bar`'s near-white background.
    var glassFill: Color { pillBackground.opacity(scheme == .dark ? 0.65 : 0.85) }
    /// Same idea as `glassFill` but accent-tinted, for the icon rail's
    /// active tab -- reads as "selected" without going fully opaque.
    var glassActiveFill: Color { accent.opacity(scheme == .dark ? 0.55 : 0.5) }
    /// Thin rim stroke tracing a glass tile's edge. Scheme-flipped (unlike
    /// most other glass tokens) so it stays visible against both a
    /// near-black and a near-white `bar`.
    var glassRim: Color { scheme == .dark ? .white.opacity(0.28) : .black.opacity(0.12) }
    /// Specular highlight blob in the tile's top-leading corner.
    var glassSheen: Color { .white.opacity(scheme == .dark ? 0.22 : 0.55) }

    var toggleOn: Color { scheme == .dark ? .hex("#30D158") : .hex("#34C759") }
    var toggleOff: Color { scheme == .dark ? .hex("#48484A") : .hex("#E2E2E5") }

    var dangerText: Color { scheme == .dark ? .hex("#FF453A") : .hex("#D92C2C") }
    var connectedDot: Color { toggleOn }
    var disconnectedDot: Color { scheme == .dark ? .hex("#6E6E73") : .hex("#B0B0B4") }
}

extension Color {
    /// Parses a `#RRGGBB` (or bare `RRGGBB`) hex string. Falls back to an
    /// unmistakable "bad hex" magenta on malformed input, mirroring
    /// `ThemeColor.color`.
    static func hex(_ hex: String, opacity: Double = 1) -> Color {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            return Color(red: 1, green: 0, blue: 1)
        }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        return Color(red: r, green: g, blue: b, opacity: opacity)
    }
}

/// An 11px bold, uppercase, tertiary-gray section header -- used atop every
/// grouped list section (`DESIGNS`, `THEMES`, `LAYERS`, `COLOR ROLES`, …).
struct SectionHeader: View {
    var title: String

    @Environment(\.colorScheme) private var colorScheme
    private var chrome: Chrome { Chrome(scheme: colorScheme) }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(chrome.textTertiary)
    }
}

/// A tappable pill/chip: rounded-rect fill + centered/leading label, built
/// from the same `ZStack` + `onTapGesture` pattern already used throughout
/// this app for custom-styled tap targets (`KeyCapView`, `PaletteChip`,
/// `DesignCellView`) since SwiftCrossUI's native `Button` can't be
/// re-skinned per-platform.
struct TapTarget<Content: View>: View {
    var background: Color
    var cornerRadius: Double
    var action: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(background)
            content()
        }
        .onTapGesture(perform: action)
    }
}

/// A 12px text pill in the titlebar toolbar group (`New`, `Open`, `Save`, …).
struct ToolbarPill: View {
    var label: String
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var chrome: Chrome { Chrome(scheme: colorScheme) }

    var body: some View {
        TapTarget(background: chrome.pillBackground, cornerRadius: 6, action: action) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(chrome.textPrimary)
        }
        .padding(EdgeInsets(top: 5, bottom: 5, leading: 10, trailing: 10))
        .fixedSize()
    }
}

/// A circular faux-glass tile behind an icon-only tap target
/// (`ToolbarIconButton`, `RailButton`). SwiftCrossUI has no backdrop-blur/
/// Material API -- its one `NSVisualEffectView` usage is internal, wired
/// only to a sidebar split view, not exposed as a general-purpose `View`
/// -- so this fakes glass with stacked translucent shapes instead: a
/// tinted base circle, a small offset highlight blob (specular sheen), and
/// a thin rim stroke. See `docs/superpowers/specs/2026-08-07-glass-icon-buttons-design.md`.
struct GlassIconTile<Content: View>: View {
    var tint: Color
    var diameter: Double
    var action: () -> Void
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var colorScheme
    private var chrome: Chrome { Chrome(scheme: colorScheme) }

    var body: some View {
        ZStack {
            Circle().fill(tint)
            Circle()
                .fill(chrome.glassSheen)
                .frame(width: diameter * 0.42, height: diameter * 0.42)
                .padding(EdgeInsets(top: Int(diameter * 0.1), bottom: 0, leading: Int(diameter * 0.12), trailing: 0))
                .frame(width: diameter, height: diameter, alignment: .topLeading)
            Circle().stroke(chrome.glassRim, style: StrokeStyle(width: 1))
            content()
        }
        .frame(width: diameter, height: diameter)
        .onTapGesture(perform: action)
    }
}

/// An icon-only glass tile in the titlebar toolbar group (`New`, `Open`,
/// `Save`, `Save As`, `Import`, `Export`) with a `.help()` tooltip carrying
/// the action name. Distinct from `ToolbarPill` (used elsewhere for
/// dynamic text pills, e.g. DSN's `+ Row`/width presets) since those have
/// no natural icon and must keep showing text.
struct ToolbarIconButton: View {
    var icon: AppIcon
    var tooltip: String
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var chrome: Chrome { Chrome(scheme: colorScheme) }

    var body: some View {
        GlassIconTile(tint: chrome.glassFill, diameter: 32, action: action) {
            if let url = IconLoader.url(for: icon, colorScheme: colorScheme) {
                Image(url).resizable().frame(width: 16, height: 16)
            }
        }
        .help(tooltip)
    }
}

/// One of the four icon-rail buttons (KEY/DSN/THM/DEV) -- a platform-native
/// icon with a `.help()` tooltip carrying the full name.
struct RailButton: View {
    var icon: AppIcon
    var tooltip: String
    var isActive: Bool
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var chrome: Chrome { Chrome(scheme: colorScheme) }

    var body: some View {
        GlassIconTile(
            tint: isActive ? chrome.glassActiveFill : chrome.glassFill,
            diameter: 40,
            action: action
        ) {
            iconImage
        }
        .help(tooltip)
    }

    /// Active tabs sit on the accent-tinted glass fill (`chrome.glassActiveFill`)
    /// -- this always uses the white-tinted ("dark" folder) icon variant
    /// when active, regardless of the app's actual color scheme, since it
    /// needs to read against that blue tint either way.
    @ViewBuilder
    private var iconImage: some View {
        if let url = IconLoader.url(for: icon, colorScheme: isActive ? .dark : colorScheme) {
            Image(url).resizable().frame(width: 22, height: 22)
        }
    }
}

/// A full-width stacked action button in an inspector column (`Save
/// Design`, `Duplicate…`, `Delete`, …). `isPrimary` gives the blue-filled
/// treatment used for the one emphasized action per pane.
struct InspectorButton: View {
    var label: String
    var isPrimary: Bool = false
    var isDestructive: Bool = false
    var isEnabled: Bool = true
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var chrome: Chrome { Chrome(scheme: colorScheme) }

    var body: some View {
        let fade = isEnabled ? 1.0 : 0.4
        TapTarget(
            background: (isPrimary ? chrome.accent : chrome.pillBackground).opacity(fade),
            cornerRadius: 7,
            action: { if isEnabled { action() } }
        ) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(
                    (isPrimary ? .white : (isDestructive ? chrome.dangerText : chrome.textPrimary))
                        .opacity(fade)
                )
        }
        .frame(height: 30)
    }
}

/// A colored presence dot (`● USB Connected`, transport cards, …).
struct StatusDot: View {
    var color: Color
    var diameter: Double = 8

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: diameter, height: diameter)
    }
}
