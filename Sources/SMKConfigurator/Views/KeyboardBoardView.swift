import SwiftCrossUI

/// Renders `editor.activeDesign`'s physical grid: one row per
/// `design.grid` row, gaps (`Cell.isGap`) skipped entirely so `HStack`
/// spacing stays uniform (a placeholder child there would get spacing on
/// both sides and double the gap).
struct KeyboardBoardView: View {
    @Environment(EditorState.self) var editor

    private struct BoardSlot: Identifiable {
        var row: Int
        var col: Int
        var widthUnits: Double
        var id: String { "\(row),\(col)" }
    }

    var body: some View {
        let design = editor.activeDesign
        VStack(spacing: 6) {
            ForEach(0..<design.rowCount, id: \.self) { r in
                let slots: [BoardSlot] = (0..<design.colCount).compactMap { c in
                    let cell = design.grid[r][c]
                    guard !cell.isGap else { return nil }
                    return BoardSlot(row: r, col: c, widthUnits: cell.width)
                }
                HStack(spacing: 6) {
                    ForEach(slots) { slot in
                        KeyCapView(row: slot.row, col: slot.col, widthUnits: slot.widthUnits)
                    }
                }
            }
        }
        .padding(16)
    }
}
