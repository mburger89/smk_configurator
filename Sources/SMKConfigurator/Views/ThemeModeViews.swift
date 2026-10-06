import MetalUI

// THM mode -- placeholders until lane 2 of the port (plan §1.7). Final names
// and initialisers.

/// THM rail mode's list column: themes, "+ New Theme…", colour roles.
struct ThemeListColumnView: Component {
    let editor: EditorState
    @Binding var draft: KeyboardTheme
    let selectTheme: @MainActor (KeyboardTheme) -> Void
    let newTheme: @MainActor () -> Void

    var content: some ElementGroup {
        PanePlaceholder(label: "Theme list — not yet ported", width: 260, background: Chrome.column)
    }
}

/// THM rail mode's main content: the board drawn with the draft theme.
struct ThemeMainContentView: Component {
    let editor: EditorState
    let draft: KeyboardTheme

    var content: some ElementGroup {
        PanePlaceholder(label: "Theme preview — not yet ported", width: nil, background: Chrome.canvas)
    }
}

/// THM rail mode's inspector: Save Theme, Duplicate…, Import…, Export….
struct ThemeInspectorView: Component {
    let draft: KeyboardTheme
    let save: @MainActor () -> Void
    let duplicate: @MainActor () -> Void
    let importTheme: @MainActor () -> Void
    let exportTheme: @MainActor () -> Void

    var content: some ElementGroup {
        PanePlaceholder(label: "Theme inspector — not yet ported", width: 300, background: Chrome.column)
    }
}
