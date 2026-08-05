import SwiftCrossUI

/// One row in the THM list column's "Color roles" section: an 18×18 swatch
/// + label + editable hex field. No native color picker exists in
/// SwiftCrossUI, so hex entry is the editing surface -- the handoff calls
/// for these fields to stay editable (not read-only), just styled to read
/// as a compact label + value row.
struct ThemeSwatchField: View {
    var label: String
    @Binding var color: ThemeColor

    @Environment(\.colorScheme) private var colorScheme
    private var chrome: Chrome { Chrome(scheme: colorScheme) }

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color.color)
                .frame(width: 18, height: 18)
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(
                            color.isValid ? chrome.dividerLight : Color.red,
                            style: StrokeStyle(width: color.isValid ? 1 : 2)
                        )
                }
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(chrome.textPrimary)
            Spacer()
            TextField("#RRGGBB", text: hexBinding)
                .font(.system(size: 10, design: .monospaced))
                .frame(width: 76)
        }
    }

    private var hexBinding: Binding<String> {
        Binding(get: { color.hex }, set: { color.hex = $0 })
    }
}
