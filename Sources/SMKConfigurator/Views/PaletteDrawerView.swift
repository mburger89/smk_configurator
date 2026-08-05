import SwiftCrossUI

/// The dense action palette below the board in KEY mode: every action the
/// firmware understands, grouped into sections and shown simultaneously
/// (not tabbed), white background, capped at 220px tall and scrollable --
/// see the handoff's "List column"/"Main content" KEY description. Tapping
/// a chip arms it (see `KeyCapView`); tapping the armed chip again disarms
/// it.
struct PaletteDrawerView: View {
    @Environment(EditorState.self) var editor
    @Environment(\.colorScheme) private var colorScheme
    private var chrome: Chrome { Chrome(scheme: colorScheme) }

    static let maxHeight: Double = 220

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                section("Letters", tokens: KeyName.letters.map { ActionToken.key($0) }, rows: 2)
                section("Numbers", tokens: KeyName.digits.map { ActionToken.key($0) })
                section("Editing & Punctuation", tokens: KeyName.editing.map { ActionToken.key($0) })
                section("Navigation", tokens: KeyName.navigation.map { ActionToken.key($0) })
                section("Modifiers", tokens: ModifierName.allCases.map { ActionToken.modifier($0) })
                layersAndSpecialSection
            }
            .padding(10)
        }
        .frame(height: Self.maxHeight)
        .background(chrome.surface)
    }

    private func section(_ title: String, tokens: [ActionToken], rows: Int = 1) -> some View {
        let chunks = chunk(tokens, into: rows)
        return VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(chrome.textTertiary)
            ScrollView(.horizontal) {
                VStack(spacing: 4) {
                    ForEach(chunks.indices, id: \.self) { i in
                        HStack(spacing: 4) {
                            ForEach(chunks[i]) { token in
                                PaletteChip(token: token)
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

    private var layersAndSpecialSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LAYERS & SPECIAL")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(chrome.textTertiary)
            HStack(spacing: 4) {
                TapTarget(background: chrome.chipBackground, cornerRadius: 4, action: {
                    editor.pendingLayerIndex = max(0, editor.pendingLayerIndex - 1)
                }) {
                    Text("–").font(.system(size: 11)).foregroundColor(chrome.textPrimary)
                }
                .frame(width: 20, height: 20)
                Text("\(editor.pendingLayerIndex)")
                    .font(.system(size: 11))
                    .foregroundColor(chrome.textPrimary)
                TapTarget(background: chrome.chipBackground, cornerRadius: 4, action: {
                    editor.pendingLayerIndex = min(15, editor.pendingLayerIndex + 1)
                }) {
                    Text("+").font(.system(size: 11)).foregroundColor(chrome.textPrimary)
                }
                .frame(width: 20, height: 20)
                PaletteChip(token: .momentaryLayer(editor.pendingLayerIndex))
                PaletteChip(token: .toggleLayer(editor.pendingLayerIndex))
                PaletteChip(token: .transparent)
                PaletteChip(token: .none)
                PaletteChip(token: .toggleConnection)
            }
        }
    }
}

/// One 11px chip in the palette drawer: `#f2f2f4` fill, hairline `#e0e0e2`
/// border, 4px radius.
private struct PaletteChip: View {
    @Environment(EditorState.self) var editor
    @Environment(\.colorScheme) private var colorScheme
    private var chrome: Chrome { Chrome(scheme: colorScheme) }
    var token: ActionToken

    var body: some View {
        let isSelected = editor.selectedToken == token

        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(chrome.chipBackground)
            Text(token.displayLabel)
                .font(.system(size: 11))
                .foregroundColor(chrome.textPrimary)
        }
        .frame(width: 44, height: 26)
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? chrome.accent : chrome.chipBorder, style: StrokeStyle(width: isSelected ? 2 : 1))
        }
        .onTapGesture {
            editor.toggleSelection(token)
        }
    }
}
