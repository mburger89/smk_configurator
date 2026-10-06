import MetalUI

/// The DSN rail mode's main content: name field + row/col controls, the grid
/// canvas, and the selected-cell width/gap footer -- a placeholder until lane 2
/// of the port (plan §1.6). Final name and initialiser.
struct DesignGridEditorView: Component {
    @Binding var draft: KeyboardDesign
    @Binding var selectedCell: DesignGridPosition?

    var content: some ElementGroup {
        PanePlaceholder(label: "Design grid — not yet ported", width: nil, background: Chrome.canvas)
    }
}
