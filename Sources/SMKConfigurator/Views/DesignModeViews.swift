import MetalUI

// DSN mode's list column and inspector -- placeholders until lane 2 of the
// port (plan §1.6). Final names and initialisers.

/// DSN rail mode's list column: designs, "+ New Design…", matrix GPIO.
struct DesignListColumnView: Component {
    let editor: EditorState
    @Binding var draft: KeyboardDesign
    let selectDesign: @MainActor (KeyboardDesign) -> Void
    let newDesign: @MainActor () -> Void

    var content: some ElementGroup {
        PanePlaceholder(label: "Design list — not yet ported", width: 260, background: Chrome.column)
    }
}

/// DSN rail mode's inspector: Save Design, Duplicate…, Delete.
struct DesignInspectorView: Component {
    let draft: KeyboardDesign
    let isExistingDesign: Bool
    let save: @MainActor () -> Void
    let duplicate: @MainActor () -> Void
    let delete: @MainActor () -> Void

    var content: some ElementGroup {
        PanePlaceholder(label: "Design inspector — not yet ported", width: 300, background: Chrome.column)
    }
}
