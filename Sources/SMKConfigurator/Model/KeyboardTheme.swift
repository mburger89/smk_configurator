import Foundation
import SwiftCrossUI

/// An RGB color stored as a hex string (`"#RRGGBB"`), so themes are easy to
/// hand-author/import as JSON and match how palettes like Dracula/Monokai
/// are usually published.
struct ThemeColor: Codable, Equatable, Hashable {
    var hex: String

    init(hex: String) {
        self.hex = hex
    }

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

    /// Whether `hex` is a valid `#RRGGBB` (or bare `RRGGBB`) string.
    var isValid: Bool {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        return digits.count == 6 && UInt32(digits, radix: 16) != nil
    }
}

/// A color scheme for the keyboard view: key background/text colors plus a
/// few role accents (modifier/layer/special/empty keys) so built-in presets
/// (Dracula, Monokai, Tokyo Night, Vaporwave) read as recognizably
/// themselves rather than just "background + font color".
struct KeyboardTheme: Codable, Equatable, Identifiable {
    var name: String
    var background: ThemeColor
    var keyBackground: ThemeColor
    var keyText: ThemeColor
    var modifierBackground: ThemeColor
    var layerBackground: ThemeColor
    var specialBackground: ThemeColor
    var emptyBackground: ThemeColor
    var accent: ThemeColor

    var id: String { name }

    /// The fill color for a keycap/palette-tile showing `token`, shared by
    /// `KeyCapView` and the drawer's `PaletteChip` so both always agree.
    func background(for token: ActionToken) -> Color {
        switch token {
        case .none: return emptyBackground.color
        case .transparent: return keyBackground.color
        case .modifier: return modifierBackground.color
        case .momentaryLayer, .toggleLayer: return layerBackground.color
        case .toggleConnection: return specialBackground.color
        case .raw: return Color(red: 1, green: 0, blue: 0)
        case .key: return keyBackground.color
        }
    }

    static let allBuiltIns: [KeyboardTheme] = [.defaultTheme, .dracula, .monokai, .tokyoNight, .vaporwave]

    /// Matches the app's original hardcoded look, before theming existed.
    static let defaultTheme = KeyboardTheme(
        name: "Default",
        background: ThemeColor(hex: "#000000"),
        keyBackground: ThemeColor(hex: "#FFFFFF"),
        keyText: ThemeColor(hex: "#000000"),
        modifierBackground: ThemeColor(hex: "#F4D35E"),
        layerBackground: ThemeColor(hex: "#EE964B"),
        specialBackground: ThemeColor(hex: "#588157"),
        emptyBackground: ThemeColor(hex: "#8A8A8A"),
        accent: ThemeColor(hex: "#4285F4")
    )

    static let dracula = KeyboardTheme(
        name: "Dracula",
        background: ThemeColor(hex: "#282A36"),
        keyBackground: ThemeColor(hex: "#44475A"),
        keyText: ThemeColor(hex: "#F8F8F2"),
        modifierBackground: ThemeColor(hex: "#BD93F9"),
        layerBackground: ThemeColor(hex: "#FFB86C"),
        specialBackground: ThemeColor(hex: "#50FA7B"),
        emptyBackground: ThemeColor(hex: "#6272A4"),
        accent: ThemeColor(hex: "#FF79C6")
    )

    static let monokai = KeyboardTheme(
        name: "Monokai",
        background: ThemeColor(hex: "#272822"),
        keyBackground: ThemeColor(hex: "#3E3D32"),
        keyText: ThemeColor(hex: "#F8F8F2"),
        modifierBackground: ThemeColor(hex: "#AE81FF"),
        layerBackground: ThemeColor(hex: "#FD971F"),
        specialBackground: ThemeColor(hex: "#A6E22E"),
        emptyBackground: ThemeColor(hex: "#75715E"),
        accent: ThemeColor(hex: "#F92672")
    )

    static let tokyoNight = KeyboardTheme(
        name: "Tokyo Night",
        background: ThemeColor(hex: "#1A1B26"),
        keyBackground: ThemeColor(hex: "#292E42"),
        keyText: ThemeColor(hex: "#C0CAF5"),
        modifierBackground: ThemeColor(hex: "#BB9AF7"),
        layerBackground: ThemeColor(hex: "#FF9E64"),
        specialBackground: ThemeColor(hex: "#9ECE6A"),
        emptyBackground: ThemeColor(hex: "#565F89"),
        accent: ThemeColor(hex: "#7AA2F7")
    )

    static let vaporwave = KeyboardTheme(
        name: "Vaporwave",
        background: ThemeColor(hex: "#2B213A"),
        keyBackground: ThemeColor(hex: "#40325C"),
        keyText: ThemeColor(hex: "#F8F8FF"),
        modifierBackground: ThemeColor(hex: "#FF6AC1"),
        layerBackground: ThemeColor(hex: "#01CDFE"),
        specialBackground: ThemeColor(hex: "#05FFA1"),
        emptyBackground: ThemeColor(hex: "#8477A6"),
        accent: ThemeColor(hex: "#B967FF")
    )

    static func blank(name: String = "New Theme") -> KeyboardTheme {
        var theme = defaultTheme
        theme.name = name
        return theme
    }
}
