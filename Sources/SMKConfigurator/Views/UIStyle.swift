import SwiftCrossUI

/// Design tokens for the "Power / Grouped List" redesign (see
/// `design_handoff_1c_power_grouped_list/README.md`, section "Design
/// Tokens") -- centralized here so every pane pulls from the same palette
/// instead of re-deriving hex values.
enum Chrome {
    /// Titlebar / icon rail / status bar background.
    static let bar = Color.hex("#F6F6F7")
    /// Main content canvas background.
    static let canvas = Color.hex("#ECECEE")
    /// List / inspector column background.
    static let column = Color.hex("#FBFBFC")
    static let divider = Color.hex("#E3E3E5")
    static let dividerLight = Color.hex("#DDDDDD")
    static let surface = Color.white

    static let accent = Color.hex("#007AFF")
    static let accentWash = Color.hex("#007AFF", opacity: 0.12)

    static let textPrimary = Color.black.opacity(0.85)
    static let textSecondary = Color.black.opacity(0.6)
    static let textTertiary = Color.black.opacity(0.45)

    static let pillBackground = Color.hex("#ECEEF0")
    static let chipBackground = Color.hex("#F2F2F4")
    static let chipBorder = Color.hex("#E0E0E2")

    static let railActiveBackground = Color.hex("#007AFF")
    static let railInactiveBackground = Color.hex("#ECEEF0")

    static let toggleOn = Color.hex("#34C759")
    static let toggleOff = Color.hex("#E2E2E5")

    static let dangerText = Color.hex("#D92C2C")
    static let connectedDot = Color.hex("#34C759")
    static let disconnectedDot = Color.hex("#B0B0B4")
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

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(Chrome.textTertiary)
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

    var body: some View {
        TapTarget(background: Chrome.pillBackground, cornerRadius: 6, action: action) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(Chrome.textPrimary)
        }
        .padding(EdgeInsets(top: 5, bottom: 5, leading: 10, trailing: 10))
        .fixedSize()
    }
}

/// One of the four icon-rail buttons (`KEY`/`DSN`/`THM`/`DEV`).
struct RailButton: View {
    var label: String
    var isActive: Bool
    var action: () -> Void

    var body: some View {
        TapTarget(
            background: isActive ? Chrome.railActiveBackground : Chrome.railInactiveBackground,
            cornerRadius: 9,
            action: action
        ) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isActive ? .white : Chrome.textSecondary)
        }
        .frame(width: 40, height: 40)
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

    var body: some View {
        let fade = isEnabled ? 1.0 : 0.4
        TapTarget(
            background: (isPrimary ? Chrome.accent : Chrome.pillBackground).opacity(fade),
            cornerRadius: 7,
            action: { if isEnabled { action() } }
        ) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(
                    (isPrimary ? .white : (isDestructive ? Chrome.dangerText : Chrome.textPrimary))
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
