import MetalUI

// KEY mode -- placeholders until lane 2 of the port (plan §1.5). The types
// carry their final names and initialisers so `ContentView` is final.

/// KEY rail mode's list column: designs, themes, layers.
struct KeyListColumnView: Component {
    let editor: EditorState
    let selectDesign: @MainActor (KeyboardDesign) -> Void
    let selectTheme: @MainActor (KeyboardTheme) -> Void

    var content: some ElementGroup {
        PanePlaceholder(label: "Key list — not yet ported", width: 260, background: Chrome.column)
    }
}

/// KEY rail mode's main content: the board over the palette drawer.
struct KeyMainContentView: Component {
    let editor: EditorState

    var content: some ElementGroup {
        PanePlaceholder(label: "Keyboard — not yet ported", width: nil, background: Chrome.canvas)
    }
}

/// KEY rail mode's inspector: Key / Matrix / Theme tabs.
struct KeyInspectorView: Component {
    let editor: EditorState

    var content: some ElementGroup {
        PanePlaceholder(label: "Key inspector — not yet ported", width: 300, background: Chrome.column)
    }
}
