import MetalUI

// Shared looks: the hex colour helper, padding insets, and the app's small
// reusable pieces -- three button styles over a real MetalUI `Button`
// (focusable, Space/Return, an accessibility press and a pressed wash for
// free; the previous build drew fake buttons out of a filled shape plus a tap
// gesture), the section header and the status dot.

extension Color {
    /// Parses a `#RRGGBB` (or bare `RRGGBB`) hex string as gamma sRGB, like
    /// SwiftUI's `Color(red:green:blue:)`. Falls back to an unmistakable "bad
    /// hex" magenta on malformed input, mirroring `ThemeColor.color`.
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

/// Per-edge padding for the legacy `.padding(_ edges:)`, which takes
/// `Edges<Length>` in CSS order (top, right, bottom, left); SwiftUI's
/// `.padding(.horizontal, n)`/`EdgeInsets` are not offered on legacy elements
/// (gap MG-11).
enum Insets {
    static func edges(top: Float = 0, leading: Float = 0, bottom: Float = 0, trailing: Float = 0) -> Edges<Length> {
        Edges(top: .pixels(Pixels(top)), right: .pixels(Pixels(trailing)),
              bottom: .pixels(Pixels(bottom)), left: .pixels(Pixels(leading)))
    }

    static func symmetric(horizontal: Float = 0, vertical: Float = 0) -> Edges<Length> {
        edges(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal)
    }
}

/// An 11px bold, uppercase, tertiary-gray section header -- used atop every
/// grouped list section (`DESIGNS`, `THEMES`, `LAYERS`, `COLOR ROLES`, …).
struct SectionHeader: Component {
    var title: String

    var content: some ElementGroup {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(Chrome.textTertiary)
    }
}

/// A 12px text pill (DSN's `+ Row`/width presets, the macro library's `New
/// macro`/`Record new`, the macro canvas's `Test run`/`Save`). `isAccent`
/// fills it with the accent and white text. A disabled pill is a disabled
/// `Button` -- `Button`'s own 0.5 look -- instead of fading every colour by
/// hand.
struct PillButton: Component {
    var label: String
    var isAccent: Bool = false
    var isEnabled: Bool = true
    var help: String? = nil
    var action: @MainActor () -> Void

    var content: some ElementGroup {
        let button = Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: isAccent ? .semibold : .regular))
                .foregroundColor(isAccent ? Color.white : Chrome.textPrimary)
                .padding(Insets.symmetric(horizontal: 10))
                .frame(height: Pixels(29))
        }
        .buttonStyle(.plain)
        .background(isAccent ? Chrome.accent : Chrome.pillBackground)
        .cornerRadius(Pixels(6))
        if let help {
            button.help(help).disabled(!isEnabled)
        } else {
            button.disabled(!isEnabled)
        }
    }
}

/// A full-width action button in an inspector column (`Save Design`,
/// `Duplicate…`, `Delete`, …). `isPrimary` gives the accent fill used for the
/// one emphasized action per pane; `isDestructive` the danger label.
struct InspectorButton: Component {
    var label: String
    var isPrimary: Bool = false
    var isDestructive: Bool = false
    var isEnabled: Bool = true
    var action: @MainActor () -> Void

    var content: some ElementGroup {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isPrimary ? Color.white : (isDestructive ? Chrome.dangerText : Chrome.textPrimary))
                .frame(maxWidth: Pixels(.infinity), minHeight: Pixels(30), maxHeight: Pixels(30))
        }
        .buttonStyle(.plain)
        .background(isPrimary ? Chrome.accent : Chrome.pillBackground)
        .cornerRadius(Pixels(7))
        .disabled(!isEnabled)
    }
}

/// One of the five icon-rail buttons (KEY/DSN/THM/DEV/MAC): a 40×40 glass
/// tile with the scheme's icon and a tooltip carrying the full name. The whole
/// tile is the button's label, so the whole tile is its hit target.
struct RailButton: Component {
    var icon: AppIcon
    var tooltip: String
    var isActive: Bool
    var action: @MainActor () -> Void

    @Environment(\.colorScheme) var colorScheme

    var content: some ElementGroup {
        Button(action: action) {
            Stack {
                iconImage
            }
            .frame(width: Pixels(40), height: Pixels(40))
        }
        .buttonStyle(.plain)
        .background(isActive ? Chrome.glassActiveFill : Chrome.glassFill)
        .cornerRadius(Pixels(9))
        .help(tooltip)
    }

    /// Active tabs sit on the accent-tinted glass, so they always use the
    /// white ("dark" folder) icon, whatever the app's scheme.
    @ElementBuilder
    private var iconImage: some ElementGroup {
        if let bitmap = IconLoader.bitmap(for: icon, colorScheme: isActive ? .dark : colorScheme) {
            Image(decorative: bitmap, scale: IconLoader.bitmapScale)
        } else {
            Text(icon.fallbackLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isActive ? Color.white : Chrome.textSecondary)
        }
    }
}

/// A coloured presence dot (`● USB Connected`, transport cards, …).
struct StatusDot: Component {
    var color: Color
    var diameter: Float = 8

    var content: some ElementGroup {
        Circle()
            .fill(color)
            .frame(width: Pixels(diameter), height: Pixels(diameter))
    }
}

/// A pane not yet rebuilt on MetalUI: its label centred on the pane's own
/// background at the pane's width (`nil`: flexible, for a main column). Used by
/// the placeholder files lane 1 of the port left for lanes 2 and 3; it goes
/// when the last of them does.
struct PanePlaceholder: Component {
    var label: String
    var width: Float?
    var background: Color

    var content: some ElementGroup {
        if let width {
            body.frame(minWidth: Pixels(width), maxWidth: Pixels(width), maxHeight: Pixels(.infinity))
                .background(background)
        } else {
            body.frame(maxWidth: Pixels(.infinity), maxHeight: Pixels(.infinity))
                .background(background)
        }
    }

    private var body: Text {
        Text(label)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(Chrome.textTertiary)
    }
}
