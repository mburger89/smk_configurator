import SwiftCrossUI

/// A cell coordinate in the DSN grid editor, distinct from `KeyPosition`
/// (which identifies a key on the *active* design for the Key inspector) --
/// this identifies a cell within whatever design is currently being
/// drafted, which may not be saved/active yet.
struct DesignGridPosition: Equatable {
    var row: Int
    var col: Int
}

/// The DSN rail mode's Main content pane: name field + row/col controls,
/// the grid canvas itself, and the selected-cell width/gap footer. Mutates
/// `draft` directly; nothing here touches `EditorState` -- saving/
/// duplicating/deleting the draft is the DSN inspector's job (see
/// `DesignInspectorView`), mirroring the click-to-arm/click-to-place
/// pattern already used for keymap editing.
struct DesignGridEditorView: View {
    @Binding var draft: KeyboardDesign
    @Binding var selectedCell: DesignGridPosition?

    @Environment(\.colorScheme) private var colorScheme
    private var chrome: Chrome { Chrome(scheme: colorScheme) }

    static let widthPresets: [Double] = [1, 1.25, 1.5, 1.75, 2, 2.25, 2.75]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                grid
                    .padding(20)
            }
            .background(Color.black)
            Divider()
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Name:")
                .font(.system(size: 12))
                .foregroundColor(chrome.textSecondary)
            TextField("Design name", text: nameBinding)
                .font(.system(size: 13))
            Spacer()
            ToolbarPill(label: "+ Row", action: addRow)
            ToolbarPill(label: "− Row", action: removeRow)
            ToolbarPill(label: "+ Col", action: addCol)
            ToolbarPill(label: "− Col", action: removeCol)
        }
        .padding(EdgeInsets(top: 10, bottom: 10, leading: 16, trailing: 16))
        .background(chrome.surface)
    }

    private var grid: some View {
        VStack(spacing: 4) {
            ForEach(0..<draft.rowCount, id: \.self) { r in
                HStack(spacing: 4) {
                    ForEach(0..<draft.colCount, id: \.self) { c in
                        DesignCellView(
                            cell: draft.grid[r][c],
                            isSelected: selectedCell == DesignGridPosition(row: r, col: c)
                        ) {
                            selectedCell = DesignGridPosition(row: r, col: c)
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let selectedCell {
                Text("Selected (\(selectedCell.row), \(selectedCell.col)):")
                    .font(.system(size: 12))
                    .foregroundColor(chrome.textSecondary)
                ForEach(Self.widthPresets, id: \.self) { preset in
                    ToolbarPill(label: presetLabel(preset)) {
                        draft.grid[selectedCell.row][selectedCell.col].width = preset
                        draft.grid[selectedCell.row][selectedCell.col].isGap = false
                    }
                }
                Spacer()
                Toggle("Gap", isOn: gapBinding(for: selectedCell))
            } else {
                Text("Select a cell to edit its width")
                    .font(.system(size: 12))
                    .foregroundColor(chrome.textTertiary)
                Spacer()
            }
        }
        .padding(EdgeInsets(top: 10, bottom: 10, leading: 16, trailing: 16))
        .background(chrome.surface)
    }

    // MARK: - Row/col mutation

    private func addRow() {
        let nextGPIO = (draft.matrix.rows.max() ?? -1) + 1
        draft.matrix.rows.append(nextGPIO)
        draft.grid.append(Array(repeating: KeyboardDesign.Cell(), count: draft.colCount))
    }

    private func removeRow() {
        guard draft.rowCount > 1 else { return }
        draft.matrix.rows.removeLast()
        draft.grid.removeLast()
        if let selectedCell, selectedCell.row >= draft.rowCount {
            self.selectedCell = nil
        }
    }

    private func addCol() {
        let nextGPIO = (draft.matrix.cols.max() ?? -1) + 1
        draft.matrix.cols.append(nextGPIO)
        for r in draft.grid.indices {
            draft.grid[r].append(KeyboardDesign.Cell())
        }
    }

    private func removeCol() {
        guard draft.colCount > 1 else { return }
        draft.matrix.cols.removeLast()
        for r in draft.grid.indices {
            draft.grid[r].removeLast()
        }
        if let selectedCell, selectedCell.col >= draft.colCount {
            self.selectedCell = nil
        }
    }

    private func presetLabel(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", w) : String(format: "%.2f", w)
    }

    // MARK: - Bindings

    private var nameBinding: Binding<String> {
        Binding(get: { draft.name }, set: { draft.name = $0 })
    }

    private func gapBinding(for position: DesignGridPosition) -> Binding<Bool> {
        Binding(
            get: { draft.grid[position.row][position.col].isGap },
            set: { draft.grid[position.row][position.col].isGap = $0 }
        )
    }
}
