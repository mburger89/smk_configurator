import MetalUI

/// The eight colour roles of a `KeyboardTheme`, in the order the THM list and
/// the KEY inspector's Theme tab show them.
enum ThemeRole: CaseIterable {
    case background, keyBackground, keyText, modifierBackground
    case layerBackground, specialBackground, emptyBackground, accent

    var label: String {
        switch self {
        case .background: "Background"
        case .keyBackground: "Key background"
        case .keyText: "Font color"
        case .modifierBackground: "Modifier keys"
        case .layerBackground: "Layer keys"
        case .specialBackground: "Special keys"
        case .emptyBackground: "Empty keys"
        case .accent: "Accent / selection"
        }
    }

    var keyPath: WritableKeyPath<KeyboardTheme, ThemeColor> {
        switch self {
        case .background: \.background
        case .keyBackground: \.keyBackground
        case .keyText: \.keyText
        case .modifierBackground: \.modifierBackground
        case .layerBackground: \.layerBackground
        case .specialBackground: \.specialBackground
        case .emptyBackground: \.emptyBackground
        case .accent: \.accent
        }
    }
}

/// A square colour sample with a hairline ring, radius 4.
struct Swatch: Component {
    var color: Color
    var side: Float
    var ring: Color
    var ringWidth: Float

    var content: some ElementGroup {
        Box()
            .frame(width: Pixels(side), height: Pixels(side))
            .background(color)
            .cornerRadius(Pixels(4))
            .border(ring, width: Pixels(ringWidth))
    }
}

/// One row of the THM list column's COLOR ROLES: an 18-point swatch, the
/// label, and an editable `#RRGGBB` field. MetalUI has no colour picker
/// (gap MG-7), so the hex field stays the editing surface. An invalid hex
/// rings the swatch in 2-point red.
struct ThemeSwatchField: Component {
    var label: String
    @Binding var color: ThemeColor

    var content: some ElementGroup {
        Row(gap: Pixels(8)) {
            Swatch(color: color.color, side: 18,
                   ring: color.isValid ? Chrome.dividerLight : Color.red,
                   ringWidth: color.isValid ? 1 : 2)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Chrome.textPrimary)
            Spacer()
            TextField("#RRGGBB", text: $color.hex)
                .font(.system(size: 10, design: .monospaced))
                .frame(width: Pixels(76))
        }
    }
}
