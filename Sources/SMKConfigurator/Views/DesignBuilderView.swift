import SwiftCrossUI

/// Visual keyboard-design builder, presented as a sheet from `ContentView`.
/// Builds a `KeyboardDesign` (grid of key widths/gaps + matrix GPIO config)
/// entirely by clicking, mirroring the click-to-arm/click-to-place pattern
/// already used for keymap editing (SwiftCrossUI has no drag gesture).
struct DesignBuilderView: View {
    @Environment(EditorState.self) var editor
    @Binding var isPresented: Bool

    @State var draft: KeyboardDesign
    @State var selectedCell: GridPosition? = nil

    /// `nil` for "New Design"; the design being replaced otherwise (needed
    /// so Delete/rename don't leave the old file behind).
    var editingExisting: KeyboardDesign?

    struct GridPosition: Equatable {
        var row: Int
        var col: Int
    }

    static let widthPresets: [Double] = [1, 1.25, 1.5, 1.75, 2, 2.25, 2.75]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            grid
            if let selectedCell {
                cellInspector(for: selectedCell)
            }
            Divider()
            matrixSection
            Spacer()
            footer
        }
        .padding(16)
        .frame(width: 720, height: 620)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Name:")
            TextField("Design name", text: nameBinding)
            Spacer()
            Button("+ Row") { addRow() }
            Button("- Row") { removeRow() }
            Button("+ Col") { addCol() }
            Button("- Col") { removeCol() }
        }
    }

    private var grid: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(0..<draft.rowCount, id: \.self) { r in
                    HStack(spacing: 4) {
                        ForEach(0..<draft.colCount, id: \.self) { c in
                            DesignCellView(
                                cell: draft.grid[r][c],
                                isSelected: selectedCell == GridPosition(row: r, col: c)
                            ) {
                                selectedCell = GridPosition(row: r, col: c)
                            }
                        }
                    }
                }
            }
        }
        .frame(height: 220)
        .background(Color.black)
    }

    private func cellInspector(for position: GridPosition) -> some View {
        HStack(spacing: 8) {
            Text("Selected (\(position.row), \(position.col)):")
            ForEach(Self.widthPresets, id: \.self) { preset in
                Button(presetLabel(preset)) {
                    draft.grid[position.row][position.col].width = preset
                    draft.grid[position.row][position.col].isGap = false
                }
            }
            Toggle("Gap", isOn: gapBinding(for: position))
        }
    }

    private var matrixSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Matrix GPIO (row strobe/sense pins, col strobe/sense pins)")
                .font(.system(size: 11))
                .foregroundColor(.gray)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    Text("Rows:")
                    ForEach(0..<draft.matrix.rows.count, id: \.self) { i in
                        TextField("", text: rowGPIOBinding(i))
                    }
                }
            }
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    Text("Cols:")
                    ForEach(0..<draft.matrix.cols.count, id: \.self) { i in
                        TextField("", text: colGPIOBinding(i))
                    }
                }
            }
            Toggle("Columns are driven (vs. rows)", isOn: colsAreDrivenBinding)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if editingExisting != nil {
                Button("Delete") {
                    if let editingExisting {
                        editor.deleteDesign(editingExisting)
                    }
                    isPresented = false
                }
            }
            Spacer()
            Button("Cancel") {
                isPresented = false
            }
            Button("Save") {
                editor.saveDesign(draft)
                isPresented = false
            }
        }
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

    private var colsAreDrivenBinding: Binding<Bool> {
        Binding(
            get: { draft.matrix.colsAreDriven != 0 },
            set: { draft.matrix.colsAreDriven = $0 ? 1 : 0 }
        )
    }

    private func gapBinding(for position: GridPosition) -> Binding<Bool> {
        Binding(
            get: { draft.grid[position.row][position.col].isGap },
            set: { draft.grid[position.row][position.col].isGap = $0 }
        )
    }

    private func rowGPIOBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { String(draft.matrix.rows[index]) },
            set: { if let value = Int($0) { draft.matrix.rows[index] = value } }
        )
    }

    private func colGPIOBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { String(draft.matrix.cols[index]) },
            set: { if let value = Int($0) { draft.matrix.cols[index] = value } }
        )
    }
}
