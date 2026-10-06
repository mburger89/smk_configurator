import MetalUI

// The app's chrome palette (port plan §3): one MetalUI app palette key
// (`ThemeColorKey`) per chrome colour, light and dark, read through the
// `Chrome` namespace. A palette colour resolves against the window's scheme by
// itself at paint time, so views never branch on the scheme to pick a colour
// (the previous `Chrome(scheme:)` struct did) and a scheme switch repaints
// everything without a rebuild of these values. The keyboard themes' colours
// are user data, not chrome: they stay literal `Color`s computed from the model
// (`Views/ThemeColor+MetalUI.swift`).

/// The chrome palette's keys. Each `defaultValue` is the light/dark pair the
/// app was designed with (`design_handoff_1c_power_grouped_list`, "Design
/// Tokens"); a theme could override any of them per variant with
/// `app.lightTheme[ChromeKeys.Bar.self] = …`, and nothing does today.
enum ChromeKeys {
    /// Icon rail and status bar background.
    enum Bar: ThemeColorKey {
        static var defaultValue: Color { Color(light: .hex("#F6F6F7"), dark: .hex("#2B2B2D")) }
    }
    /// Main content canvas background.
    enum Canvas: ThemeColorKey {
        static var defaultValue: Color { Color(light: .hex("#ECECEE"), dark: .hex("#1E1E20")) }
    }
    /// List / inspector column background, library rows, step cards.
    enum Column: ThemeColorKey {
        static var defaultValue: Color { Color(light: .hex("#FBFBFC"), dark: .hex("#252527")) }
    }
    /// Pane dividers. MetalUI's `Divider()` draws the theme's `.separator`,
    /// which `ChromeTheme.apply(to:)` sets to these same values.
    enum Divider: ThemeColorKey {
        static var defaultValue: Color { Color(light: .hex("#E3E3E5"), dark: .hex("#3A3A3C")) }
    }
    /// Swatch rings, cards, the slot track, step borders.
    enum DividerLight: ThemeColorKey {
        static var defaultValue: Color { Color(light: .hex("#DDDDDD"), dark: .hex("#333335")) }
    }
    /// Palette drawer, DSN header/footer, cards.
    enum Surface: ThemeColorKey {
        static var defaultValue: Color { Color(light: .hex("#FFFFFF"), dark: .hex("#2C2C2E")) }
    }
    /// Selection text, rings, primary buttons, links.
    enum Accent: ThemeColorKey {
        static var defaultValue: Color { Color(light: .hex("#007AFF"), dark: .hex("#0A84FF")) }
    }
    /// Selected row/card fill.
    enum AccentWash: ThemeColorKey {
        static var defaultValue: Color {
            Color(light: .hex("#007AFF", opacity: 0.12), dark: .hex("#0A84FF", opacity: 0.18))
        }
    }
    /// Body text.
    enum TextPrimary: ThemeColorKey {
        static var defaultValue: Color { Color(light: Color.black.opacity(0.85), dark: Color.white.opacity(0.85)) }
    }
    /// Secondary text.
    enum TextSecondary: ThemeColorKey {
        static var defaultValue: Color { Color(light: Color.black.opacity(0.6), dark: Color.white.opacity(0.6)) }
    }
    /// Captions and section headers.
    enum TextTertiary: ThemeColorKey {
        static var defaultValue: Color { Color(light: Color.black.opacity(0.45), dark: Color.white.opacity(0.45)) }
    }
    /// Pills and inspector buttons.
    enum PillBackground: ThemeColorKey {
        static var defaultValue: Color { Color(light: .hex("#ECEEF0"), dark: .hex("#3A3A3C")) }
    }
    /// Palette/modifier chips, step-type rows, badges.
    enum ChipBackground: ThemeColorKey {
        static var defaultValue: Color { Color(light: .hex("#F2F2F4"), dark: .hex("#323234")) }
    }
    /// Chip hairlines, the layer-picker box.
    enum ChipBorder: ThemeColorKey {
        static var defaultValue: Color { Color(light: .hex("#E0E0E2"), dark: .hex("#48484A")) }
    }
    /// Inactive rail tile: translucent rather than opaque, since MetalUI has
    /// no backdrop-blur material (gap MG-9). Light needs a higher alpha than
    /// dark to stay visible against `bar`'s near-white.
    enum GlassFill: ThemeColorKey {
        static var defaultValue: Color {
            Color(light: .hex("#ECEEF0", opacity: 0.97), dark: .hex("#3A3A3C", opacity: 0.90))
        }
    }
    /// Active rail tile: accent-tinted glass.
    enum GlassActiveFill: ThemeColorKey {
        static var defaultValue: Color {
            Color(light: .hex("#007AFF", opacity: 0.75), dark: .hex("#0A84FF", opacity: 0.80))
        }
    }
    /// Warnings, destructive labels, delete glyphs.
    enum DangerText: ThemeColorKey {
        static var defaultValue: Color { Color(light: .hex("#D92C2C"), dark: .hex("#FF453A")) }
    }
    /// Connected status dots.
    enum ConnectedDot: ThemeColorKey {
        static var defaultValue: Color { Color(light: .hex("#34C759"), dark: .hex("#30D158")) }
    }
    /// Disconnected status dots.
    enum DisconnectedDot: ThemeColorKey {
        static var defaultValue: Color { Color(light: .hex("#B0B0B4"), dark: .hex("#6E6E73")) }
    }
}

/// The chrome colours as `Color`s, so a call site reads `Chrome.textPrimary`.
/// Each is a palette colour: it names its key, not a value, and resolves
/// against the scheme of the element it paints.
enum Chrome {
    static let bar = Color(ChromeKeys.Bar.self)
    static let canvas = Color(ChromeKeys.Canvas.self)
    static let column = Color(ChromeKeys.Column.self)
    static let divider = Color(ChromeKeys.Divider.self)
    static let dividerLight = Color(ChromeKeys.DividerLight.self)
    static let surface = Color(ChromeKeys.Surface.self)
    static let accent = Color(ChromeKeys.Accent.self)
    static let accentWash = Color(ChromeKeys.AccentWash.self)
    static let textPrimary = Color(ChromeKeys.TextPrimary.self)
    static let textSecondary = Color(ChromeKeys.TextSecondary.self)
    static let textTertiary = Color(ChromeKeys.TextTertiary.self)
    static let pillBackground = Color(ChromeKeys.PillBackground.self)
    static let chipBackground = Color(ChromeKeys.ChipBackground.self)
    static let chipBorder = Color(ChromeKeys.ChipBorder.self)
    static let glassFill = Color(ChromeKeys.GlassFill.self)
    static let glassActiveFill = Color(ChromeKeys.GlassActiveFill.self)
    static let dangerText = Color(ChromeKeys.DangerText.self)
    static let connectedDot = Color(ChromeKeys.ConnectedDot.self)
    static let disconnectedDot = Color(ChromeKeys.DisconnectedDot.self)
}

/// MetalUI's own controls (checkbox, segmented picker, slider, focus ring,
/// `Divider`, drawn menus) paint from the window theme's built-in tokens; these
/// overrides make them agree with the palette (port plan §3.4). Nothing else of
/// `Theme.light`/`Theme.dark` is overridden.
enum ChromeTheme {
    @MainActor
    static func apply(to app: App) {
        app.lightTheme.accent = .rgb(0x007AFF)
        app.lightTheme.separator = .rgb(0xE3E3E5)
        app.lightTheme.surface = .rgb(0xFFFFFF)
        app.lightTheme.textPrimary = .rgb(0x000000)

        app.darkTheme.accent = .rgb(0x0A84FF)
        app.darkTheme.separator = .rgb(0x3A3A3C)
        app.darkTheme.surface = .rgb(0x2C2C2E)
        app.darkTheme.textPrimary = .rgb(0xFFFFFF)
    }
}
