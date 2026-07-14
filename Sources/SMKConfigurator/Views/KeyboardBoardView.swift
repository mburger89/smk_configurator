import SwiftCrossUI

/// Renders `editor.activeDesign`'s physical grid: one row per
/// `design.grid` row, gaps (`Cell.isGap`) skipped entirely so `HStack`
/// spacing stays uniform (a placeholder child there would get spacing on
/// both sides and double the gap).
struct KeyboardBoardView: View {
    @Environment(EditorState.self) var editor

    var body: some View {
        let design = editor.activeDesign
        VStack(spacing: 6) {
            ForEach(0..<design.rowCount, id: \.self) { r in
                HStack(spacing: 6) {
                    ForEach(design.visibleSlots(row: r)) { slot in
                        KeyCapView(row: slot.row, col: slot.col, widthUnits: slot.widthUnits)
                    }
                }
            }
        }
        .padding(16)
    }
}
