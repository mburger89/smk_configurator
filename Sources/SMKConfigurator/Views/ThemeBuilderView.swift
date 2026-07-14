import SwiftCrossUI

/// Visual theme editor, presented as a sheet from `ContentView`. Every
/// color role is edited as a hex string (no native color picker in
/// SwiftCrossUI); a live preview strip shows the effect immediately without
/// touching the real editor state until Save.
struct ThemeBuilderView: View {
    @Environment(EditorState.self) var editor
    @Binding var isPresented: Bool

    @State var draft: KeyboardTheme

    /// `nil` for "New Theme"; the theme being replaced otherwise.
    var editingExisting: KeyboardTheme?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Name:")
                        TextField("Theme name", text: nameBinding)
                    }
                    Divider()
                    ThemeSwatchField(label: "Background", color: bind(\.background))
                    ThemeSwatchField(label: "Key background", color: bind(\.keyBackground))
                    ThemeSwatchField(label: "Font color", color: bind(\.keyText))
                    ThemeSwatchField(label: "Modifier keys", color: bind(\.modifierBackground))
                    ThemeSwatchField(label: "Layer keys", color: bind(\.layerBackground))
                    ThemeSwatchField(label: "Special keys", color: bind(\.specialBackground))
                    ThemeSwatchField(label: "Empty keys", color: bind(\.emptyBackground))
                    ThemeSwatchField(label: "Accent / selection", color: bind(\.accent))
                    Divider()
                    preview
                }
            }
            footer
        }
        .padding(16)
        .frame(width: 420, height: 640)
    }

    /// Renders the real board (in the user's own keymap) with `draft`'s
    /// colors instead of the active theme's, so every role a real board
    /// actually uses is visible live as fields change, not just samples.
    private var preview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Preview")
                .font(.system(size: 11))
                .foregroundColor(.gray)
            ThemePreviewBoardView(theme: draft)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if editingExisting != nil {
                Button("Delete") {
                    if let editingExisting {
                        editor.deleteTheme(editingExisting)
                    }
                    isPresented = false
                }
            }
            Spacer()
            Button("Cancel") {
                isPresented = false
            }
            Button("Save") {
                editor.saveTheme(draft)
                isPresented = false
            }
        }
    }

    private var nameBinding: Binding<String> {
        Binding(get: { draft.name }, set: { draft.name = $0 })
    }

    private func bind(_ keyPath: WritableKeyPath<KeyboardTheme, ThemeColor>) -> Binding<ThemeColor> {
        Binding(get: { draft[keyPath: keyPath] }, set: { draft[keyPath: keyPath] = $0 })
    }
}
