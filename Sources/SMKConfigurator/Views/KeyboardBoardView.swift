import SwiftCrossUI

/// Renders `editor.activeDesign`'s physical grid: one row per
/// `design.grid` row, gaps (`Cell.isGap`) skipped entirely so `HStack`
/// spacing stays uniform (a placeholder child there would get spacing on
/// both sides and double the gap).
///
/// Used both as the KEY mode board (editable, `editor.activeTheme`) and the
/// THM mode live preview (read-only, whichever theme is being edited) --
/// `theme`/`interactive` forward straight through to `KeyCapView`.
struct KeyboardBoardView: View {
    @Environment(EditorState.self) var editor

    var theme: KeyboardTheme? = nil
    var interactive: Bool = true

    var body: some View {
        let design = editor.activeDesign
        VStack(spacing: 6) {
            ForEach(0..<design.rowCount, id: \.self) { r in
                HStack(spacing: 6) {
                    ForEach(design.visibleSlots(row: r)) { slot in
                        KeyCapView(
                            row: slot.row,
                            col: slot.col,
                            widthUnits: slot.widthUnits,
                            theme: theme,
                            interactive: interactive
                        )
                    }
                }
            }
        }
        .padding(16)
    }
}
