import SwiftCrossUI

/// KEY rail mode's List column: three stacked grouped sections (Designs,
/// Themes, Layers) so switching any of them doesn't require leaving KEY
/// mode. `selectDesign`/`selectTheme` are supplied by `ContentView` so the
/// DSN/THM inline draft workspaces stay in sync with whatever gets picked
/// here too.
struct KeyListColumnView: View {
    @Environment(EditorState.self) var editor
    @Environment(\.colorScheme) private var colorScheme
    private var chrome: Chrome { Chrome(scheme: colorScheme) }
    var selectDesign: (KeyboardDesign) -> Void
    var selectTheme: (KeyboardTheme) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionHeader(title: "Designs")
                    ForEach(editor.availableDesigns) { design in
                        designRow(design)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    SectionHeader(title: "Themes")
                    ForEach(editor.availableThemes) { theme in
                        themeRow(theme)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    SectionHeader(title: "Layers")
                    ForEach(editor.document.layers.indices, id: \.self) { index in
                        layerRow(index)
                    }
                }
            }
            .padding(EdgeInsets(top: 12, bottom: 12, leading: 10, trailing: 10))
        }
        .frame(width: 260)
        .frame(maxHeight: .infinity)
        .background(chrome.column)
    }

    private func designRow(_ design: KeyboardDesign) -> some View {
        let isSelected = editor.activeDesign.id == design.id
        return ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? chrome.accentWash : Color.clear)
            HStack(spacing: 6) {
                Text(design.name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? chrome.accent : chrome.textPrimary)
                Spacer()
                Text("\(design.rowCount)×\(design.colCount)")
                    .font(.system(size: 11))
                    .foregroundColor(chrome.textTertiary)
            }
            .padding(EdgeInsets(top: 6, bottom: 6, leading: 8, trailing: 8))
        }
        .onTapGesture { selectDesign(design) }
    }

    private func themeRow(_ theme: KeyboardTheme) -> some View {
        let isSelected = editor.activeTheme.id == theme.id
        return ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? chrome.accentWash : Color.clear)
            HStack(spacing: 8) {
                Circle().fill(theme.accent.color).frame(width: 10, height: 10)
                Text(theme.name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? chrome.accent : chrome.textPrimary)
                Spacer()
            }
            .padding(EdgeInsets(top: 6, bottom: 6, leading: 8, trailing: 8))
        }
        .onTapGesture { selectTheme(theme) }
    }

    private func layerRow(_ index: Int) -> some View {
        let isSelected = editor.currentLayer == index
        return ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? chrome.accentWash : Color.clear)
            HStack(spacing: 8) {
                Text("⋮⋮")
                    .font(.system(size: 11))
                    .foregroundColor(chrome.textTertiary)
                Text("Layer \(index)" + (index == 0 ? " — Base" : ""))
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? chrome.accent : chrome.textPrimary)
                Spacer()
            }
            .padding(EdgeInsets(top: 6, bottom: 6, leading: 8, trailing: 8))
        }
        .onTapGesture { editor.currentLayer = index }
    }
}

/// KEY rail mode's Main content: the board, in a dark card colored by the
/// active theme, with the dense action palette below it.
struct KeyMainContentView: View {
    @Environment(EditorState.self) var editor
    @Environment(\.colorScheme) private var colorScheme
    private var chrome: Chrome { Chrome(scheme: colorScheme) }

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            ScrollView {
                KeyboardBoardView()
                    .background(editor.activeTheme.background.color)
                    .cornerRadius(10)
            }
            PaletteDrawerView()
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(chrome.canvas)
    }
}

/// KEY rail mode's Inspector: a Key/Matrix/Theme tab row, with the Key tab
/// showing the currently-inspected keycap's label/canonical string (and,
/// when Advanced Mode is on, its matrix row/col, GPIO pins, and driven
/// axis), plus Reassign/Clear actions.
struct KeyInspectorView: View {
    @Environment(EditorState.self) var editor
    @Environment(\.colorScheme) private var colorScheme
    private var chrome: Chrome { Chrome(scheme: colorScheme) }
    @State var tab: InspectorTab = .key

    enum InspectorTab: String, CaseIterable {
        case key = "Key", matrix = "Matrix", theme = "Theme"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            tabRow
            switch tab {
            case .key: keyDetail
            case .matrix: matrixDetail
            case .theme: themeDetail
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 300)
        .frame(maxHeight: .infinity)
        .background(chrome.column)
    }

    private var tabRow: some View {
        HStack(spacing: 4) {
            ForEach(InspectorTab.allCases, id: \.self) { candidate in
                TapTarget(
                    background: tab == candidate ? chrome.accent : chrome.pillBackground,
                    cornerRadius: 6,
                    action: { tab = candidate }
                ) {
                    Text(candidate.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(tab == candidate ? .white : chrome.textPrimary)
                }
                .frame(height: 26)
            }
        }
    }

    // MARK: - Key tab

    private var hasValidKeySelection: Bool {
        guard let position = editor.selectedKeyPosition else { return false }
        let design = editor.activeDesign
        return position.row < design.rowCount && position.col < design.colCount
    }

    private var selectedToken: ActionToken {
        guard let position = editor.selectedKeyPosition else { return .none }
        return editor.action(row: position.row, col: position.col)
    }

    private var keyDetail: some View {
        VStack(alignment: .leading, spacing: 10) {
            if hasValidKeySelection, let position = editor.selectedKeyPosition {
                Text(selectedToken.displayLabel.isEmpty ? "—" : selectedToken.displayLabel)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(chrome.textPrimary)
                Text("\(selectedToken.canonicalString) · layer \(editor.currentLayer)")
                    .font(.system(size: 12))
                    .foregroundColor(chrome.textSecondary)

                if editor.showAdvanced {
                    Divider()
                    let design = editor.activeDesign
                    VStack(alignment: .leading, spacing: 4) {
                        detailLine("Row · Col", "\(position.row) · \(position.col)")
                        detailLine("Row GPIO", "\(design.matrix.rows[position.row])")
                        detailLine("Col GPIO", "\(design.matrix.cols[position.col])")
                        detailLine("Driven axis", design.matrix.colsAreDriven != 0 ? "Cols" : "Rows")
                        detailLine("Canonical", selectedToken.canonicalString, monospaced: true)
                    }
                } else {
                    detailLine("Row · Col", "\(position.row) · \(position.col)")
                }

                Divider()
                HStack(spacing: 8) {
                    InspectorButton(
                        label: "Reassign",
                        isPrimary: true,
                        isEnabled: editor.selectedToken != nil
                    ) {
                        editor.reassignSelectedKey()
                    }
                    InspectorButton(label: "Clear") {
                        editor.clearSelectedKey()
                    }
                }
            } else {
                Text("No key selected")
                    .font(.system(size: 12))
                    .foregroundColor(chrome.textTertiary)
            }
        }
    }

    private func detailLine(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(chrome.textTertiary)
            Spacer()
            Text(value)
                .font(.system(size: 11, design: monospaced ? .monospaced : nil))
                .foregroundColor(chrome.textSecondary)
        }
    }

    // MARK: - Matrix tab

    private var matrixDetail: some View {
        let design = editor.activeDesign
        return VStack(alignment: .leading, spacing: 8) {
            Text(design.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(chrome.textPrimary)
            Text("\(design.rowCount) rows · \(design.colCount) cols")
                .font(.system(size: 12))
                .foregroundColor(chrome.textSecondary)
            Divider()
            Text("Rows: " + design.matrix.rows.map(String.init).joined(separator: ", "))
                .font(.system(size: 11))
                .foregroundColor(chrome.textSecondary)
            Text("Cols: " + design.matrix.cols.map(String.init).joined(separator: ", "))
                .font(.system(size: 11))
                .foregroundColor(chrome.textSecondary)
            Text(design.matrix.colsAreDriven != 0 ? "Columns are driven" : "Rows are driven")
                .font(.system(size: 11))
                .foregroundColor(chrome.textTertiary)
        }
    }

    // MARK: - Theme tab

    private var themeDetail: some View {
        let theme = editor.activeTheme
        return VStack(alignment: .leading, spacing: 8) {
            Text(theme.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(chrome.textPrimary)
            Divider()
            themeSwatchRow("Background", theme.background)
            themeSwatchRow("Key background", theme.keyBackground)
            themeSwatchRow("Font color", theme.keyText)
            themeSwatchRow("Modifier keys", theme.modifierBackground)
            themeSwatchRow("Layer keys", theme.layerBackground)
            themeSwatchRow("Special keys", theme.specialBackground)
            themeSwatchRow("Empty keys", theme.emptyBackground)
            themeSwatchRow("Accent / selection", theme.accent)
        }
    }

    private func themeSwatchRow(_ label: String, _ color: ThemeColor) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color.color)
                .frame(width: 14, height: 14)
                .overlay {
                    RoundedRectangle(cornerRadius: 4).stroke(chrome.dividerLight, style: StrokeStyle(width: 1))
                }
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(chrome.textPrimary)
            Spacer()
            Text(color.hex)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(chrome.textTertiary)
        }
    }
}
