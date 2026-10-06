import MetalUI

// The MACROS step editor's palette column and canvas header -- placeholders
// until lane 3 of the port (plan §1.10). Final names and initialisers.
// (`MacroStepType` moved to `Model/MacroUITypes.swift`.)

/// The step editor's left column: ADD STEP, CAPTURE, SLOT, Back to library.
struct MacroStepPaletteView: Component {
    let editor: EditorState

    var content: some ElementGroup {
        PanePlaceholder(label: "Step palette — not yet ported", width: 212, background: Chrome.column)
    }
}

/// The step editor's canvas header: the macro's name, Test run, Save.
struct MacroCanvasHeaderView: Component {
    let editor: EditorState

    var content: some ElementGroup {
        Row(gap: Pixels(12)) {
            Text(editor.currentMacro?.name ?? "")
                .font(.system(size: 19, weight: .semibold))
                .foregroundColor(Chrome.textPrimary)
            Text("Canvas header — not yet ported")
                .font(.system(size: 12))
                .foregroundColor(Chrome.textTertiary)
            Spacer()
            PillButton(label: "Back to library") { [editor] in editor.closeMacro() }
        }
        .padding(Pixels(16))
        .frame(maxWidth: Pixels(.infinity))
    }
}
