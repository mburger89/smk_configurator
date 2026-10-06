import MetalUI

/// The dense action palette below the board in KEY mode: every action the
/// firmware understands, grouped into sections shown together (not tabbed),
/// as tall as `PaletteLayout.maxHeight` allows with the rarer sections
/// scrolling below the fold. Its sections, chips per row and height bounds
/// are `PaletteLayout`'s (pinned by `PaletteDrawerLayoutTests`); this view only
/// draws them.
///
/// Drag a chip onto a key to place it there; click a chip to assign it to the
/// inspected key (port plan §2.2 W5 -- the previous build's
/// click-to-arm/click-to-place is gone).
struct PaletteDrawerView: Component {
    let editor: EditorState

    var content: some ElementGroup {
        ScrollView(.vertical) {
            Column(gap: Pixels(Float(PaletteLayout.sectionSpacing))) {
                // First, not last: it holds the only controls with no other
                // path in the UI -- the layer picker feeding MO/TG, and
                // trans/none/toggle_conn -- and whatever sits at the bottom is
                // reachable only by scrolling.
                layersAndSpecialSection
                for section in PaletteLayout.keySections {
                    PaletteSection(editor: editor, title: section.title, tokens: section.tokens, rows: section.rows)
                }
                macroSection
            }
            .alignItems(.flexStart)
            .padding(Pixels(Float(PaletteLayout.outerPadding)))
        }
        .frame(maxWidth: Pixels(.infinity),
               minHeight: Pixels(Float(PaletteLayout.minHeight)),
               maxHeight: Pixels(Float(PaletteLayout.maxHeight)))
        .background(Chrome.surface)
        .cornerRadius(Pixels(10))
    }

    private func title(_ text: String) -> Text {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(Chrome.textTertiary)
    }

    private var layersAndSpecialSection: some Element {
        Column(gap: Pixels(Float(PaletteLayout.sectionTitleSpacing))) {
            title("Layers & special")
            Row(gap: Pixels(12)) {
                layerPickerGroup
                Row(gap: Pixels(PaletteChip.spacing)) {
                    PaletteChip(editor: editor, token: .transparent)
                    PaletteChip(editor: editor, token: .none)
                    PaletteChip(editor: editor, token: .toggleConnection)
                }
            }
            .frame(height: Pixels(Float(PaletteLayout.layersRowHeight)))
        }
        .alignItems(.flexStart)
    }

    /// The layer number and its `Stepper`, then the MO/TG chips it feeds,
    /// boxed together with a "→" so it reads as one control ("this number is
    /// which layer MO/TG jump to"). The previous build drew the − and + as two
    /// fake buttons around the number (port plan §2.2 W15).
    private var layerPickerGroup: some Element {
        let editor = editor
        let layerIndex = Binding<Int>(
            get: { editor.pendingLayerIndex },
            set: { editor.pendingLayerIndex = min(max(0, $0), editor.maxAssignableLayerIndex) }
        )
        return Row(gap: Pixels(4)) {
            Text("\(editor.pendingLayerIndex)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Chrome.textPrimary)
                .frame(width: Pixels(16))
            Stepper("", value: layerIndex, in: 0...max(0, editor.maxAssignableLayerIndex))
                .accessibilityLabel("Layer for MO and TG")
            Text("→")
                .font(.system(size: 11))
                .foregroundColor(Chrome.textTertiary)
            PaletteChip(editor: editor, token: .momentaryLayer(editor.pendingLayerIndex))
            PaletteChip(editor: editor, token: .toggleLayer(editor.pendingLayerIndex))
        }
        .padding(Pixels(4))
        .background(Chrome.chipBackground.opacity(0.5))
        .cornerRadius(Pixels(6))
        .border(Chrome.chipBorder, width: Pixels(1))
    }

    /// One chip per saved macro, pinned to one row whatever the count -- with
    /// zero it still renders ("No macros yet.") -- so the drawer's height never
    /// depends on the document (`PaletteLayout.macroSectionHeight`). Past a
    /// row it says how many it is not showing; the MACROS rail mode lists
    /// every one.
    private var macroSection: some Element {
        let tokens = PaletteLayout.macroTokens(for: editor.document)
        let rowHeight = Pixels(Float(PaletteLayout.chipRowHeight))
        return Column(gap: Pixels(Float(PaletteLayout.sectionTitleSpacing))) {
            title("Macros")
            if tokens.isEmpty {
                Text("No macros yet.")
                    .font(.system(size: 11))
                    .foregroundColor(Chrome.textTertiary)
                    .frame(height: rowHeight)
            } else {
                Row(gap: Pixels(PaletteChip.spacing)) {
                    for token in tokens.prefix(PaletteLayout.chipsPerRow) {
                        PaletteChip(editor: editor, token: token)
                    }
                    if tokens.count > PaletteLayout.chipsPerRow {
                        Text("+\(tokens.count - PaletteLayout.chipsPerRow) more")
                            .font(.system(size: 11))
                            .foregroundColor(Chrome.textTertiary)
                    }
                }
                .frame(height: rowHeight)
            }
        }
        .alignItems(.flexStart)
    }
}

/// One generated key group (or Modifiers) in the drawer, split into `rows`
/// fixed rows by `PaletteLayout.chunk` -- never wider than `chipsPerRow`,
/// since the drawer scrolls vertically only.
struct PaletteSection: Component {
    let editor: EditorState
    var title: String
    var tokens: [ActionToken]
    var rows: Int

    var content: some ElementGroup {
        Column(gap: Pixels(Float(PaletteLayout.sectionTitleSpacing))) {
            PaletteSectionTitle(text: title)
            Column(gap: Pixels(Float(PaletteLayout.chipRowSpacing))) {
                for chunk in PaletteLayout.chunk(tokens, into: rows) {
                    Row(gap: Pixels(PaletteChip.spacing)) {
                        for token in chunk {
                            PaletteChip(editor: editor, token: token)
                        }
                    }
                }
            }
            .alignItems(.flexStart)
        }
        .alignItems(.flexStart)
    }
}

/// A drawer section's 10-point bold uppercase tertiary title.
struct PaletteSectionTitle: Component {
    var text: String

    var content: some ElementGroup {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(Chrome.textTertiary)
    }
}

/// One 44×26 chip in the palette drawer: `chipBackground` fill, a 1-point
/// `chipBorder` hairline, radius 4, an 11-point label. A real `Button`: a
/// click assigns its action to the inspected key; dragged, it carries the
/// action to whichever key it is dropped on (`KeyCapView`).
struct PaletteChip: Component {
    let editor: EditorState
    var token: ActionToken

    static let width: Float = 44
    static let spacing: Float = 8

    var content: some ElementGroup {
        let editor = editor
        let token = token
        Button {
            guard let position = editor.selectedKeyPosition else { return }
            editor.assign(token, row: position.row, col: position.col)
        } label: {
            Text(token.displayLabel)
                .font(.system(size: 11))
                .foregroundColor(Chrome.textPrimary)
                .frame(width: Pixels(Self.width), height: Pixels(Float(PaletteLayout.chipRowHeight)))
        }
        .buttonStyle(.plain)
        .background(Chrome.chipBackground)
        .cornerRadius(Pixels(4))
        .border(Chrome.chipBorder, width: Pixels(1))
        .help(helpText)
        .draggable(PaletteDrop.payload(for: token))
    }

    /// A macro chip names its macro (its label is only "M<id>"); every other
    /// chip says what dragging and clicking do.
    private var helpText: String {
        if case .macro(let id) = token, let name = editor.macroName(for: id) {
            return name
        }
        return "Drag onto a key, or click to assign to the selected key"
    }
}
