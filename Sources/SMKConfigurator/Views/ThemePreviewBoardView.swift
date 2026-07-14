import SwiftCrossUI

/// A small-scale rendering of the active design, using the user's real
/// keymap labels but colored with `theme` instead of `editor.activeTheme` --
/// used by `ThemeBuilderView` so a theme's colors can be previewed live,
/// across every role a real board actually has, before it's saved.
struct ThemePreviewBoardView: View {
    @Environment(EditorState.self) var editor
    var theme: KeyboardTheme

    static let unit: Double = 20
    static let spacing: Double = 2

    var body: some View {
        let design = editor.activeDesign
        VStack(spacing: 3) {
            ForEach(0..<design.rowCount, id: \.self) { r in
                HStack(spacing: 3) {
                    ForEach(design.visibleSlots(row: r)) { slot in
                        previewKey(row: slot.row, col: slot.col, widthUnits: slot.widthUnits)
                    }
                }
            }
        }
        .padding(8)
        .background(theme.background.color)
    }

    private func previewKey(row: Int, col: Int, widthUnits: Double) -> some View {
        let token = editor.action(row: row, col: col)
        let width = widthUnits * Self.unit + (widthUnits - 1) * Self.spacing

        return ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(theme.background(for: token))
            Text(token.displayLabel)
                .font(.system(size: 7))
                .foregroundColor(theme.keyText.color)
        }
        .frame(width: width, height: Self.unit)
    }
}
