import SwiftCrossUI

/// A vertical list of layer tabs, meant to sit in a left sidebar, plus
/// add/remove controls. Layer 0 always exists (`LayerEngine.isLayerActive`
/// treats it as permanently active).
struct LayerTabsView: View {
    @Environment(EditorState.self) var editor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Layers")
                .foregroundColor(.gray)
            ForEach(editor.document.layers.indices, id: \.self) { index in
                let isSelected = editor.currentLayer == index
                let theme = editor.activeTheme
                ZStack {
                    Circle()
                        .fill(isSelected ? theme.accent.color : theme.keyBackground.color)
                    Text("\(index)")
                        .foregroundColor(theme.keyText.color)
                }
                .frame(width: 36, height: 36)
                .onTapGesture {
                    editor.currentLayer = index
                }
            }
            Button("+ Layer") {
                editor.addLayer()
            }
            Button("Delete\nLayer") {
                editor.removeCurrentLayer()
            }
        }
        .frame(width: 100)
    }
}
