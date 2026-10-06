import MetalUI

// The model's colour-bearing values mapped onto MetalUI's `Color` and
// `ColorScheme`. They live here, not in `Model/`, so the model compiles on
// Linux and Windows without any UI dependency (port plan §4.3).

extension ThemeColor {
    /// The literal colour this hex draws as -- user data, so a literal `Color`
    /// that does not change with the app's scheme. Malformed hex draws an
    /// unmistakable magenta.
    var color: Color {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            return Color(red: 1, green: 0, blue: 1)  // unmistakable "bad hex" magenta
        }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        return Color(red: r, green: g, blue: b)
    }
}

extension MacroStepType {
    /// The badge fill, sourced from the same per-theme keycap roles
    /// `KeyCapView`/`KeyboardTheme.background(for:)` already use -- not a
    /// fixed literal, so the palette stays in sync with whichever theme is
    /// active instead of inventing a second, parallel color set. `nil`
    /// means the neutral pill background (`Chrome.pillBackground`), used
    /// for Repeat block since it has no keycap role of its own.
    func badgeColor(theme: KeyboardTheme) -> Color? {
        switch self {
        case .keystroke: return theme.keyBackground.color
        case .text: return theme.emptyBackground.color
        case .delay: return theme.modifierBackground.color
        case .layer: return theme.layerBackground.color
        case .repeatBlock: return nil
        }
    }
}

extension AppearanceMode {
    /// `nil` means "defer to the OS" -- passed straight to
    /// `.preferredColorScheme` at the window root (`ContentView`).
    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }
}
