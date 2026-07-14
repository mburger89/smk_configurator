import SwiftCrossUI

/// A labeled color swatch + hex text field, the building block for
/// `ThemeBuilderView`'s eight color roles. No native color picker exists in
/// SwiftCrossUI, so hex entry mirrors the GPIO-number `TextField` pattern
/// already used in `DesignBuilderView`.
struct ThemeSwatchField: View {
    var label: String
    @Binding var color: ThemeColor

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color.color)
                .frame(width: 22, height: 22)
                .overlay {
                    if !color.isValid {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.red, style: StrokeStyle(width: 2))
                    }
                }
            Text(label)
                .font(.system(size: 11))
            TextField("#RRGGBB", text: hexBinding)
        }
    }

    private var hexBinding: Binding<String> {
        Binding(get: { color.hex }, set: { color.hex = $0 })
    }
}
