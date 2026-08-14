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
    var glassFill: Color { pillBackground.opacity(scheme == .dark ? 0.9 : 0.97) }
    /// Same idea as `glassFill` but accent-tinted, for the icon rail's
    /// active tab -- reads as "selected" without going fully opaque.
    var glassActiveFill: Color { accent.opacity(scheme == .dark ? 0.8 : 0.75) }

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
    /// `nil` selects a `Circle` (see the `circleBackground:` initializer)
    /// instead of a `RoundedRectangle`.
    var cornerRadius: Double?
    /// Optional hairline stroke traced around the shape -- used by the
    /// icon-only glass tiles (`ToolbarIconButton`) to read as a distinct
    /// button against a translucent background; omitted everywhere else.
    var border: Color?
    var action: () -> Void
    @ViewBuilder var content: () -> Content

    init(
        background: Color,
        cornerRadius: Double,
        action: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.background = background
        self.cornerRadius = cornerRadius
        self.border = nil
        self.action = action
        self.content = content
    }

    /// A circular tap target, optionally bordered -- the "glass tile"
    /// look shared by icon-only buttons.
    init(
        circleBackground background: Color,
        border: Color? = nil,
        action: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.background = background
        self.cornerRadius = nil
        self.border = border
        self.action = action
        self.content = content
    }

    var body: some View {
        ZStack {
            if let cornerRadius {
                RoundedRectangle(cornerRadius: cornerRadius).fill(background)
                if let border {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(border, style: StrokeStyle(width: 1))
                }
            } else {
                Circle().fill(background)
                if let border {
                    Circle().stroke(border, style: StrokeStyle(width: 1))
                }
            }
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

/// An icon-only glass tile in the titlebar toolbar group (`New`, `Open`,
/// `Save`, `Save As`, `Import`, `Export`) with a `.help()` tooltip carrying
/// the action name. Distinct from `ToolbarPill` (used elsewhere for
/// dynamic text pills, e.g. DSN's `+ Row`/width presets) since those have
/// no natural icon and must keep showing text. A circular `TapTarget`
/// (`chrome.glassFill` translucent tint, `chrome.chipBorder` hairline
/// stroke) -- SwiftCrossUI has no backdrop-blur/Material API, so a plain
/// translucent fill is the closest approximation to a real glass material.
struct ToolbarIconButton: View {
    var icon: AppIcon
    var tooltip: String
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var chrome: Chrome { Chrome(scheme: colorScheme) }

    var body: some View {
        TapTarget(circleBackground: chrome.glassFill, border: chrome.chipBorder, action: action) {
            if let url = IconLoader.url(for: icon, colorScheme: colorScheme) {
                Image(url).resizable().frame(width: 15, height: 15)
            } else {
                Text(icon.fallbackLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(chrome.textPrimary)
            }
        }
        .frame(width: 30, height: 30)
        .help(tooltip)
    }
}

/// One of the four icon-rail buttons (KEY/DSN/THM/DEV) -- a platform-native
/// icon with a `.help()` tooltip carrying the full name. Rounded-rect
/// (unlike the titlebar's circular `ToolbarIconButton`), but keeps the
/// same translucent glass tint colors.
struct RailButton: View {
    var icon: AppIcon
    var tooltip: String
    var isActive: Bool
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var chrome: Chrome { Chrome(scheme: colorScheme) }

    var body: some View {
        TapTarget(
            background: isActive ? chrome.glassActiveFill : chrome.glassFill,
            cornerRadius: 9,
            action: action
        ) {
            iconImage
        }
        .frame(width: 40, height: 40)
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
        } else {
            Text(icon.fallbackLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isActive ? .white : chrome.textSecondary)
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
