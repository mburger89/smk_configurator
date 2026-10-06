import MetalUI

/// Draws `editor.activeDesign`'s physical grid on a card in the theme's
/// background colour: one row per design row, gaps (`Cell.isGap`) skipped so
/// the row spacing stays uniform (a placeholder child would get spacing on
/// both sides and double the gap).
///
/// Used both as the KEY mode board (editable, `editor.activeTheme`) and the
/// THM mode live preview (read-only, the theme being edited) -- `theme` and
/// `interactive` go straight through to `KeyCapView`.
struct KeyboardBoardView: Component {
    let editor: EditorState
    var theme: KeyboardTheme? = nil
    var interactive: Bool = true

    static let rowSpacing: Float = 6
    static let padding: Float = 16

    /// The board card's natural height for `design`: its rows, the gaps
    /// between them and the card's padding. `KeyMainContentView` caps the
    /// board's scroll area at it (gap MG-14).
    static func naturalHeight(of design: KeyboardDesign) -> Float {
        let rows = Float(design.rowCount)
        return rows * KeyCapView.unit + max(0, rows - 1) * rowSpacing + 2 * padding
    }

    var content: some ElementGroup {
        let design = editor.activeDesign
        Column(gap: Pixels(Self.rowSpacing)) {
            for r in 0..<design.rowCount {
                Row(gap: Pixels(KeyCapView.spacing)) {
                    for slot in design.visibleSlots(row: r) {
                        KeyCapView(editor: editor, row: slot.row, col: slot.col,
                                   widthUnits: slot.widthUnits, theme: theme, interactive: interactive)
                    }
                }
            }
        }
        .alignItems(.flexStart)
        .padding(Pixels(Self.padding))
        .background((theme ?? editor.activeTheme).background.color)
        .cornerRadius(Pixels(10))
    }
}
