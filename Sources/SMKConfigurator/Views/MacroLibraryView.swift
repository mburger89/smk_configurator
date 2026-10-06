import MetalUI

/// MACROS rail mode's library: the whole-body table of every macro -- a
/// placeholder until lane 3 of the port (plan §1.9). Final name and
/// initialiser. (`MacroLibraryRow`, `MacroLibraryFilter`,
/// `CollectionFilterOption` and `MacroLibraryColumn` moved to
/// `Model/MacroLibraryModel.swift`.)
struct MacroLibraryView: Component {
    let editor: EditorState

    var content: some ElementGroup {
        PanePlaceholder(label: "Macro library — not yet ported", width: nil, background: Chrome.canvas)
    }
}
