import MetalUI

/// MACROS mode's step-editor inspector: Step / Macro / Timing tabs -- a
/// placeholder until lane 3 of the port (plan §1.10). Final name and
/// initialiser. (`MacroInspectorTab` moved to `Model/MacroUITypes.swift`.)
struct MacroInspectorView: Component {
    let editor: EditorState

    var content: some ElementGroup {
        PanePlaceholder(label: "Macro inspector — not yet ported", width: 248, background: Chrome.column)
    }
}
