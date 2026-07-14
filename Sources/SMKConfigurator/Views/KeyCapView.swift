import SwiftCrossUI

/// One physical key. Tapping it either "picks up" its current action (if
/// nothing is selected from the drawer) or places the currently-selected
/// action onto it -- the click-to-select/click-to-place substitute for
/// drag-and-drop described in the plan (SwiftCrossUI has no drag gesture as
/// of v0.8.0).
struct KeyCapView: View {
    @Environment(EditorState.self) var editor

    var row: Int
    var col: Int
    var widthUnits: Double

    static let unit: Double = 46
    static let spacing: Double = 4

    var body: some View {
        let token = editor.action(row: row, col: col)
        let width = widthUnits * Self.unit + (widthUnits - 1) * Self.spacing
        let isSelected = editor.selectedToken == token && token != .none
        let theme = editor.activeTheme

        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(theme.background(for: token))
            Text(token.displayLabel)
                .font(.system(size: 12))
                .foregroundColor(theme.keyText.color)
        }
        .frame(width: width, height: Self.unit)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(theme.accent.color, style: StrokeStyle(width: 2))
            }
        }
        .onTapGesture {
            if let selected = editor.selectedToken {
                editor.assign(selected, row: row, col: col)
            } else {
                editor.selectedToken = token
            }
        }
    }
}
