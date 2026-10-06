import MetalUI

/// The DSN rail mode's main content: the name field and the row/column pills
/// on top, the grid on the "physical board" black in a scroll area, and the
/// selected cell's width presets and Gap toggle below. It edits `draft`
/// directly and never touches `EditorState`: saving, duplicating and deleting
/// the draft are the DSN inspector's (`DesignInspectorView`).
struct DesignGridEditorView: Component {
    @Binding var draft: KeyboardDesign
    @Binding var selectedCell: DesignGridPosition?

    static let widthPresets: [Double] = [1, 1.25, 1.5, 1.75, 2, 2.25, 2.75]

    var content: some ElementGroup {
        pane {
            Column {
                header
                Divider()
                ScrollView(.vertical) {
                    grid
                }
                .frame(maxWidth: Pixels(.infinity), minHeight: Pixels(0), maxHeight: Pixels(.infinity))
                .background(Color.black)
                Divider()
                footer
            }
            .alignItems(.stretch)
            .frame(maxWidth: Pixels(.infinity), maxHeight: Pixels(.infinity))
            .background(Chrome.canvas)
        }
    }

    private var header: some Element {
        let draft = $draft
        let selection = $selectedCell
        return Row(gap: Pixels(10)) {
            Text("Name:")
                .font(.system(size: 12))
                .foregroundColor(Chrome.textSecondary)
            TextField("Design name", text: $draft.name)
                .font(.system(size: 13))
                .frame(width: Pixels(220))
            Spacer()
            PillButton(label: "+ Row") { DesignGridEditing.addRow(to: &draft.wrappedValue) }
            PillButton(label: "− Row") {
                DesignGridEditing.removeRow(from: &draft.wrappedValue, selection: &selection.wrappedValue)
            }
            PillButton(label: "+ Col") { DesignGridEditing.addColumn(to: &draft.wrappedValue) }
            PillButton(label: "− Col") {
                DesignGridEditing.removeColumn(from: &draft.wrappedValue, selection: &selection.wrappedValue)
            }
        }
        .padding(Insets.symmetric(horizontal: 16, vertical: 10))
        .background(Chrome.surface)
    }

    private var grid: some Element {
        let selection = $selectedCell
        return Column(gap: Pixels(DesignCellView.spacing)) {
            for r in 0..<draft.rowCount {
                Row(gap: Pixels(DesignCellView.spacing)) {
                    for c in 0..<draft.colCount {
                        DesignCellView(cell: draft.grid[r][c],
                                       isSelected: selectedCell == DesignGridPosition(row: r, col: c)) {
                            selection.wrappedValue = DesignGridPosition(row: r, col: c)
                        }
                    }
                }
            }
        }
        .alignItems(.flexStart)
        .padding(Pixels(20))
    }

    @ElementBuilder
    private var footer: some ElementGroup {
        if let selectedCell {
            DesignCellFooter(draft: $draft, position: selectedCell)
        } else {
            Row {
                Text("Select a cell to edit its width")
                    .font(.system(size: 12))
                    .foregroundColor(Chrome.textTertiary)
                Spacer()
            }
            .padding(Insets.symmetric(horizontal: 16, vertical: 10))
            .frame(minHeight: Pixels(49))
            .background(Chrome.surface)
        }
    }
}

/// The DSN footer for a selected cell: "Selected (r, c):", the width
/// presets, and the Gap toggle.
struct DesignCellFooter: Component {
    @Binding var draft: KeyboardDesign
    let position: DesignGridPosition

    var content: some ElementGroup {
        let draft = $draft
        let position = position
        Row(gap: Pixels(8)) {
            Text("Selected (\(position.row), \(position.col)):")
                .font(.system(size: 12))
                .foregroundColor(Chrome.textSecondary)
            for preset in DesignGridEditorView.widthPresets {
                PillButton(label: DesignCellView.label(forWidth: preset)) {
                    DesignGridEditing.setWidth(preset, at: position, in: &draft.wrappedValue)
                }
            }
            Spacer()
            Toggle("Gap", isOn: Binding(
                get: { DesignGridEditing.isGap(at: position, in: draft.wrappedValue) },
                set: { DesignGridEditing.setGap($0, at: position, in: &draft.wrappedValue) }
            ))
        }
        .padding(Insets.symmetric(horizontal: 16, vertical: 10))
        .frame(minHeight: Pixels(49))
        .background(Chrome.surface)
    }
}

/// The DSN grid editor's edits, as plain functions over a draft design and
/// the selected cell, so they are testable without a window
/// (`DesignGridEditingTests`). Behaviour is the previous build's, unchanged.
enum DesignGridEditing {
    /// Appends a row of 1U keys wired to the next unused row GPIO.
    static func addRow(to design: inout KeyboardDesign) {
        let nextGPIO = (design.matrix.rows.max() ?? -1) + 1
        design.matrix.rows.append(nextGPIO)
        design.grid.append(Array(repeating: KeyboardDesign.Cell(), count: design.colCount))
    }

    /// Drops the last row (never the only one), clearing a selection that
    /// falls outside the grid.
    static func removeRow(from design: inout KeyboardDesign, selection: inout DesignGridPosition?) {
        guard design.rowCount > 1 else { return }
        design.matrix.rows.removeLast()
        design.grid.removeLast()
        if let cell = selection, cell.row >= design.rowCount {
            selection = nil
        }
    }

    /// Appends a column of 1U keys wired to the next unused column GPIO.
    static func addColumn(to design: inout KeyboardDesign) {
        let nextGPIO = (design.matrix.cols.max() ?? -1) + 1
        design.matrix.cols.append(nextGPIO)
        for r in design.grid.indices {
            design.grid[r].append(KeyboardDesign.Cell())
        }
    }

    /// Drops the last column (never the only one), clearing a selection that
    /// falls outside the grid.
    static func removeColumn(from design: inout KeyboardDesign, selection: inout DesignGridPosition?) {
        guard design.colCount > 1 else { return }
        design.matrix.cols.removeLast()
        for r in design.grid.indices {
            design.grid[r].removeLast()
        }
        if let cell = selection, cell.col >= design.colCount {
            selection = nil
        }
    }

    /// A width preset makes the cell a key of that width (no longer a gap).
    static func setWidth(_ width: Double, at position: DesignGridPosition, in design: inout KeyboardDesign) {
        guard contains(position, design) else { return }
        design.grid[position.row][position.col].width = width
        design.grid[position.row][position.col].isGap = false
    }

    static func isGap(at position: DesignGridPosition, in design: KeyboardDesign) -> Bool {
        contains(position, design) && design.grid[position.row][position.col].isGap
    }

    static func setGap(_ isGap: Bool, at position: DesignGridPosition, in design: inout KeyboardDesign) {
        guard contains(position, design) else { return }
        design.grid[position.row][position.col].isGap = isGap
    }

    private static func contains(_ position: DesignGridPosition, _ design: KeyboardDesign) -> Bool {
        position.row >= 0 && position.row < design.grid.count
            && position.col >= 0 && position.col < design.grid[position.row].count
    }
}
