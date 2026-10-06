import MetalUI

// KEY mode (port plan §1.5): the list column (designs, themes, layers), the
// board over the palette drawer, and the Key / Matrix / Theme inspector. The
// small list/inspector building blocks the DSN, THM and DEV panes share live
// here too.

/// Erases a pane's element type behind `AnyElement` (in a `Box`, since
/// `AnyElement` takes an `Element`). Every list, main and inspector pane wraps
/// its content in this.
///
/// Why: a `Component`'s layout record stores its whole content value and that
/// content's layout (`ComponentLayout`), so `ContentView`'s mode `switch`es
/// carry the full static type of every pane of every mode at once. With the
/// four real panes in place that record overflowed an 8 MB main-thread stack
/// in a debug build, in every mode, even where the pane is not shown
/// (gap MG-15). Erasing at the pane boundary keeps each pane's layout behind
/// one box.
@MainActor
func pane<Content: ElementGroup>(@ElementBuilder _ content: () -> Content) -> AnyElement {
    AnyElement(Box(content: content))
}

/// A selectable list row shared by the KEY, DSN and THM list columns: the
/// whole row is one plain `Button`, filled with `accentWash` while selected.
/// (The previous build stacked a filled shape under the label with a tap
/// gesture -- a fake button, port plan §2.2 W1.)
struct ListRowButton<Label: ElementGroup>: Component {
    var isSelected: Bool
    var action: @MainActor () -> Void
    var label: Label

    init(isSelected: Bool, action: @escaping @MainActor () -> Void, @ElementBuilder label: () -> Label) {
        self.isSelected = isSelected
        self.action = action
        self.label = label()
    }

    var content: some ElementGroup {
        Button(action: action) {
            Row(gap: Pixels(8)) {
                label
            }
            .padding(Insets.symmetric(horizontal: 8, vertical: 6))
            .frame(maxWidth: Pixels(.infinity), alignment: .leading)
        }
        .buttonStyle(.plain)
        .background(isSelected ? Chrome.accentWash : Color.clear)
        .cornerRadius(Pixels(6))
    }
}

/// A design row: the name (semibold and accent while active) and its
/// trailing "R×C".
struct DesignRow: Component {
    let design: KeyboardDesign
    let isSelected: Bool
    let select: @MainActor () -> Void

    var content: some ElementGroup {
        ListRowButton(isSelected: isSelected, action: select) {
            Text(design.name)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? Chrome.accent : Chrome.textPrimary)
            Spacer()
            Text("\(design.rowCount)×\(design.colCount)")
                .font(.system(size: 11))
                .foregroundColor(Chrome.textTertiary)
        }
    }
}

/// A theme row: a 10-point dot in the theme's own accent (user data, a
/// literal colour), then the name.
struct ThemeRow: Component {
    let theme: KeyboardTheme
    let isSelected: Bool
    let select: @MainActor () -> Void

    var content: some ElementGroup {
        ListRowButton(isSelected: isSelected, action: select) {
            StatusDot(color: theme.accent.color, diameter: 10)
            Text(theme.name)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? Chrome.accent : Chrome.textPrimary)
            Spacer()
        }
    }
}

/// An accent text link under a list ("+ New Design…", "+ New Theme…").
struct LinkButton: Component {
    var label: String
    var action: @MainActor () -> Void

    var content: some ElementGroup {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(Chrome.accent)
                .padding(Insets.edges(top: 4, leading: 8))
        }
        .buttonStyle(.plain)
    }
}

/// A list column's frame: 260 wide, full height, scrolling, `Chrome.column`,
/// sections 18 apart.
struct ListColumn<Body: ElementGroup>: Component {
    var body: Body

    init(@ElementBuilder body: () -> Body) {
        self.body = body()
    }

    var content: some ElementGroup {
        ScrollView(.vertical) {
            Column(gap: Pixels(18)) {
                body
            }
            .alignItems(.stretch)
            .padding(Insets.symmetric(horizontal: 10, vertical: 12))
        }
        .frame(minWidth: Pixels(260), maxWidth: Pixels(260), maxHeight: Pixels(.infinity))
        .background(Chrome.column)
    }
}

/// A list section: a header and its rows, `spacing` apart, full width.
struct ListSection<Rows: ElementGroup>: Component {
    var spacing: Float
    var rows: Rows

    init(spacing: Float = 4, @ElementBuilder rows: () -> Rows) {
        self.spacing = spacing
        self.rows = rows()
    }

    var content: some ElementGroup {
        Column(gap: Pixels(spacing)) {
            rows
        }
        .alignItems(.stretch)
    }
}

/// An inspector column's frame: 300 wide, full height, padding 14, content
/// from the top, `Chrome.column`.
struct InspectorColumn<Body: ElementGroup>: Component {
    var spacing: Float
    var body: Body

    init(spacing: Float = 10, @ElementBuilder body: () -> Body) {
        self.spacing = spacing
        self.body = body()
    }

    var content: some ElementGroup {
        Column(gap: Pixels(spacing)) {
            body
        }
        .alignItems(.stretch)
        .padding(Pixels(14))
        .frame(minWidth: Pixels(300), maxWidth: Pixels(300), maxHeight: Pixels(.infinity), alignment: .top)
        .background(Chrome.column)
    }
}

/// An inspector's 13-point semibold title and its 12-point secondary
/// subtitle ("Design actions", "Theme actions", …).
struct InspectorHeading: Component {
    var title: String
    var subtitle: String? = nil

    var content: some ElementGroup {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(Chrome.textPrimary)
        if let subtitle {
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundColor(Chrome.textSecondary)
        }
    }
}

/// A "label ……… value" line in an inspector.
struct DetailLine: Component {
    var label: String
    var value: String
    var size: Double = 11
    var monospaced = false

    var content: some ElementGroup {
        Row(gap: Pixels(8)) {
            Text(label)
                .font(.system(size: size))
                .foregroundColor(Chrome.textTertiary)
            Spacer()
            Text(value)
                .font(.system(size: size, design: monospaced ? .monospaced : nil))
                .foregroundColor(Chrome.textSecondary)
        }
    }
}

/// KEY rail mode's list column: three grouped sections (Designs, Themes,
/// Layers), so switching any of them doesn't mean leaving KEY mode.
/// `selectDesign`/`selectTheme` come from `ContentView`, so the DSN/THM draft
/// workspaces follow whatever is picked here.
struct KeyListColumnView: Component {
    let editor: EditorState
    let selectDesign: @MainActor (KeyboardDesign) -> Void
    let selectTheme: @MainActor (KeyboardTheme) -> Void

    /// The layer row under the pointer, which shows its delete glyph.
    @State var hoveredLayer: Int? = nil
    /// The layer the delete alert asks about, and whether it is up.
    @State var layerToDelete: Int? = nil
    @State var confirmingDelete = false

    var content: some ElementGroup {
        pane {
            ListColumn {
                ListSection {
                    SectionHeader(title: "Designs")
                    for design in editor.availableDesigns {
                        DesignRow(design: design, isSelected: editor.activeDesign.id == design.id) { [selectDesign] in
                            selectDesign(design)
                        }
                    }
                }
                ListSection {
                    SectionHeader(title: "Themes")
                    for theme in editor.availableThemes {
                        ThemeRow(theme: theme, isSelected: editor.activeTheme.id == theme.id) { [selectTheme] in
                            selectTheme(theme)
                        }
                    }
                }
                ListSection {
                    Row {
                        SectionHeader(title: "Layers")
                        Spacer()
                        addLayerChip
                    }
                    for index in editor.document.layers.indices {
                        LayerRow(editor: editor, index: index, hoveredLayer: $hoveredLayer,
                                 layerToDelete: $layerToDelete, confirmingDelete: $confirmingDelete)
                    }
                }
            }
            .alert("Delete Layer \(layerToDelete ?? 0)?", isPresented: $confirmingDelete,
                   presenting: layerToDelete) { [editor] index in
                Button("Delete", role: .destructive) { editor.removeLayer(at: index) }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    /// The LAYERS header's trailing "+": adds a blank transparent layer,
    /// disabled at `EditorState.maxLayerCount` -- the one disabled gate and
    /// `Button`'s own disabled look, not a hand-faded colour (§2.2 W3).
    private var addLayerChip: some ElementGroup {
        let editor = editor
        return Button {
            editor.addLayer()
        } label: {
            Text("+")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Chrome.textPrimary)
                .frame(width: Pixels(20), height: Pixels(20))
        }
        .buttonStyle(.plain)
        .background(Chrome.chipBackground)
        .cornerRadius(Pixels(4))
        .help("Add a layer")
        .disabled(editor.document.layers.count >= EditorState.maxLayerCount)
    }
}

/// One layer row: "⋮⋮ Layer n" (" — Base" for 0); a click makes it the
/// current layer. While hovered (never layer 0, which the firmware always
/// treats as present) a trailing delete glyph asks to delete it. The glyph is
/// a button nested inside the row's button -- the topmost hit target wins --
/// where the previous build had to make them siblings (§2.2 W9). The hover
/// and the alert's state are the list column's, so one alert serves every row.
struct LayerRow: Component {
    let editor: EditorState
    let index: Int
    @Binding var hoveredLayer: Int?
    @Binding var layerToDelete: Int?
    @Binding var confirmingDelete: Bool

    var content: some ElementGroup {
        let editor = editor
        let index = index
        let isSelected = editor.currentLayer == index
        let hovered = $hoveredLayer
        Box {
            ListRowButton(isSelected: isSelected, action: { editor.currentLayer = index }) {
                Text("⋮⋮")
                    .font(.system(size: 11))
                    .foregroundColor(Chrome.textTertiary)
                Text("Layer \(index)" + (index == 0 ? " — Base" : ""))
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? Chrome.accent : Chrome.textPrimary)
                Spacer()
                if hoveredLayer == index && index != 0 {
                    deleteGlyph
                }
            }
        }
        .onHover { inside in
            if inside {
                hovered.wrappedValue = index
            } else if hovered.wrappedValue == index {
                hovered.wrappedValue = nil
            }
        }
    }

    private var deleteGlyph: some Element {
        let index = index
        let layerToDelete = $layerToDelete
        let confirming = $confirmingDelete
        // A monochrome glyph: colour emoji ("🗑") are not drawn (gap MG-6).
        return Button {
            layerToDelete.wrappedValue = index
            confirming.wrappedValue = true
        } label: {
            Text("✕")
                .font(.system(size: 11))
                .foregroundColor(Chrome.dangerText)
                .padding(Insets.symmetric(horizontal: 4))
        }
        .buttonStyle(.plain)
        .help("Delete Layer \(index)")
    }
}

/// KEY rail mode's main content: the board in its theme-coloured card, with
/// the palette drawer below it.
struct KeyMainContentView: Component {
    let editor: EditorState

    var content: some ElementGroup {
        pane {
            let boardHeight = max(Float(WindowMetrics.boardMinHeight),
                                  KeyboardBoardView.naturalHeight(of: editor.activeDesign))
            Column(gap: Pixels(16)) {
                // The board's scroll area grows to the board's own height and no
                // further, so the drawer below gets the rest up to its maximum.
                // The previous build served the drawer first with
                // `.layoutPriority(1)`, which the legacy stacks do not offer
                // (gap MG-14).
                ScrollView(.vertical) {
                    Column {
                        KeyboardBoardView(editor: editor)
                    }
                    .alignItems(.center)
                }
                .frame(maxWidth: Pixels(.infinity),
                       minHeight: Pixels(Float(WindowMetrics.boardMinHeight)),
                       maxHeight: Pixels(boardHeight))
                PaletteDrawerView(editor: editor)
            }
            .alignItems(.stretch)
            .padding(Pixels(20))
            .frame(maxWidth: Pixels(.infinity), maxHeight: Pixels(.infinity), alignment: .top)
            .background(Chrome.canvas)
        }
    }
}

/// KEY rail mode's inspector: Key / Matrix / Theme tabs. The Key tab shows the
/// inspected key's label and canonical string (with Advanced Mode, its matrix
/// position, GPIO pins and driven axis) and Clear.
struct KeyInspectorView: Component {
    let editor: EditorState

    enum Tab: Hashable {
        case key, matrix, theme
    }

    @State var tab: Tab = .key

    var content: some ElementGroup {
        pane {
            InspectorColumn(spacing: 14) {
                // A segmented picker, where the previous build hand-built a row of
                // fake tab buttons (§2.2 W7).
                Picker("", selection: $tab) {
                    Text("Key").tag(Tab.key)
                    Text("Matrix").tag(Tab.matrix)
                    Text("Theme").tag(Tab.theme)
                }
                switch tab {
                case .key: keyDetail
                case .matrix: matrixDetail
                case .theme: themeDetail
                }
            }
        }
    }

    // MARK: Key tab

    private var inspectedPosition: KeyPosition? {
        guard let position = editor.selectedKeyPosition else { return nil }
        let design = editor.activeDesign
        guard position.row < design.rowCount, position.col < design.colCount else { return nil }
        return position
    }

    @ElementBuilder
    private var keyDetail: some ElementGroup {
        if let position = inspectedPosition {
            let token = editor.action(row: position.row, col: position.col)
            let design = editor.activeDesign
            Column(gap: Pixels(10)) {
                Text(token.displayLabel.isEmpty ? "—" : token.displayLabel)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Chrome.textPrimary)
                Text("\(token.canonicalString) · layer \(editor.currentLayer)")
                    .font(.system(size: 12))
                    .foregroundColor(Chrome.textSecondary)
                if editor.showAdvanced {
                    Divider()
                    Column(gap: Pixels(4)) {
                        DetailLine(label: "Row · Col", value: "\(position.row) · \(position.col)")
                        DetailLine(label: "Row GPIO", value: "\(design.matrix.rows[position.row])")
                        DetailLine(label: "Col GPIO", value: "\(design.matrix.cols[position.col])")
                        DetailLine(label: "Driven axis", value: design.matrix.colsAreDriven != 0 ? "Cols" : "Rows")
                        DetailLine(label: "Canonical", value: token.canonicalString, monospaced: true)
                    }
                    .alignItems(.stretch)
                } else {
                    DetailLine(label: "Row · Col", value: "\(position.row) · \(position.col)")
                }
                Divider()
                // Reassign went with click-to-arm (§2.2 W5): a chip is dragged
                // onto a key, or clicked to assign it to this one.
                InspectorButton(label: "Clear") { [editor] in
                    editor.clearSelectedKey()
                }
            }
            .alignItems(.stretch)
        } else {
            Text("No key selected")
                .font(.system(size: 12))
                .foregroundColor(Chrome.textTertiary)
        }
    }

    // MARK: Matrix tab

    private var matrixDetail: some Element {
        let design = editor.activeDesign
        return Column(gap: Pixels(8)) {
            InspectorHeading(title: design.name, subtitle: "\(design.rowCount) rows · \(design.colCount) cols")
            Divider()
            Text("Rows: " + design.matrix.rows.map(String.init).joined(separator: ", "))
                .font(.system(size: 11))
                .foregroundColor(Chrome.textSecondary)
            Text("Cols: " + design.matrix.cols.map(String.init).joined(separator: ", "))
                .font(.system(size: 11))
                .foregroundColor(Chrome.textSecondary)
            Text(design.matrix.colsAreDriven != 0 ? "Columns are driven" : "Rows are driven")
                .font(.system(size: 11))
                .foregroundColor(Chrome.textTertiary)
        }
        .alignItems(.stretch)
    }

    // MARK: Theme tab

    private var themeDetail: some Element {
        let theme = editor.activeTheme
        return Column(gap: Pixels(8)) {
            InspectorHeading(title: theme.name)
            Divider()
            for role in ThemeRole.allCases {
                ThemeSwatchRow(label: role.label, color: theme[keyPath: role.keyPath])
            }
        }
        .alignItems(.stretch)
    }
}

/// A read-only theme role in the KEY inspector's Theme tab: a 14-point
/// swatch, the role, its hex.
struct ThemeSwatchRow: Component {
    var label: String
    var color: ThemeColor

    var content: some ElementGroup {
        Row(gap: Pixels(8)) {
            Swatch(color: color.color, side: 14, ring: Chrome.dividerLight, ringWidth: 1)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Chrome.textPrimary)
            Spacer()
            Text(color.hex)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Chrome.textTertiary)
        }
    }
}
