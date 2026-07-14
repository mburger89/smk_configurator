import SwiftCrossUI

/// The bottom drawer: every action the firmware understands, grouped into
/// sections. Tapping a tile selects it (see `KeyCapView`); tapping the
/// selected tile again deselects it.
struct PaletteDrawerView: View {
    @Environment(EditorState.self) var editor

    var body: some View {
        VStack(spacing: 0) {
            resizeControl
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    section("Letters", tokens: KeyName.letters.map { ActionToken.key($0) }, rows: 2)
                    section("Numbers", tokens: KeyName.digits.map { ActionToken.key($0) })
                    section("Editing & Punctuation", tokens: KeyName.editing.map { ActionToken.key($0) })
                    section("Navigation", tokens: KeyName.navigation.map { ActionToken.key($0) })
                    section("Modifiers", tokens: ModifierName.allCases.map { ActionToken.modifier($0) })
                    layerSection
                    section("Special", tokens: [.transparent, .none, .toggleConnection])
                }
                .padding(10)
            }
            .frame(height: editor.drawerHeight)
        }
        .background(editor.activeTheme.background.color)
    }

    private var resizeControl: some View {
        HStack(spacing: 8) {
            Text("Drawer size")
                .font(.system(size: 11))
                .foregroundColor(.gray)
            Slider(value: drawerHeightBinding, in: EditorState.drawerHeightRange)
            Text("\(Int(editor.drawerHeight))")
                .font(.system(size: 11))
                .foregroundColor(.gray)
        }
        .padding(EdgeInsets(top: 6, bottom: 0, leading: 10, trailing: 10))
    }

    private var drawerHeightBinding: Binding<Double> {
        Binding(get: { editor.drawerHeight }, set: { editor.drawerHeight = $0 })
    }

    private func section(_ title: String, tokens: [ActionToken], rows: Int = 1) -> some View {
        let chunks = chunk(tokens, into: rows)
        return VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.gray)
            ScrollView(.horizontal) {
                VStack(spacing: 6) {
                    ForEach(chunks.indices, id: \.self) { i in
                        HStack(spacing: 6) {
                            ForEach(chunks[i]) { token in
                                PaletteTile(token: token)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Splits `tokens` into `rows` roughly-equal, left-to-right chunks (e.g.
    /// a-z into two rows of 13) rather than wrapping automatically, since
    /// SwiftCrossUI has no wrapping stack/grid layout.
    private func chunk(_ tokens: [ActionToken], into rows: Int) -> [[ActionToken]] {
        guard rows > 1 else { return [tokens] }
        let perRow = Int((Double(tokens.count) / Double(rows)).rounded(.up))
        return stride(from: 0, to: tokens.count, by: perRow).map {
            Array(tokens[$0..<min($0 + perRow, tokens.count)])
        }
    }

    private var layerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Layers")
                .font(.system(size: 11))
                .foregroundColor(.gray)
            HStack(spacing: 6) {
                Button("-") {
                    editor.pendingLayerIndex = max(0, editor.pendingLayerIndex - 1)
                }
                Text("\(editor.pendingLayerIndex)")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                Button("+") {
                    editor.pendingLayerIndex = min(15, editor.pendingLayerIndex + 1)
                }
                PaletteTile(token: .momentaryLayer(editor.pendingLayerIndex))
                PaletteTile(token: .toggleLayer(editor.pendingLayerIndex))
            }
        }
    }
}

private struct PaletteTile: View {
    @Environment(EditorState.self) var editor
    var token: ActionToken

    var body: some View {
        let isSelected = editor.selectedToken == token
        let theme = editor.activeTheme

        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(theme.background(for: token))
            Text(token.displayLabel)
                .font(.system(size: 12))
                .foregroundColor(theme.keyText.color)
        }
        .frame(width: 44, height: 34)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(theme.accent.color, style: StrokeStyle(width: 2))
            }
        }
        .onTapGesture {
            editor.toggleSelection(token)
        }
    }
}
