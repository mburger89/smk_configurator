import SwiftCrossUI

/// DSN rail mode's List column: the Designs list (same row styling as KEY
/// mode) plus a "+ New Design…" link and a read-out of the draft's matrix
/// GPIO wiring.
struct DesignListColumnView: View {
    @Environment(EditorState.self) var editor
    @Binding var draft: KeyboardDesign
    var selectDesign: (KeyboardDesign) -> Void
    var newDesign: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionHeader(title: "Designs")
                    ForEach(editor.availableDesigns) { design in
                        designRow(design)
                    }
                    Text("+ New Design…")
                        .font(.system(size: 13))
                        .foregroundColor(Chrome.accent)
                        .padding(EdgeInsets(top: 4, bottom: 0, leading: 8, trailing: 0))
                        .onTapGesture { newDesign() }
                }
                matrixSummary
            }
            .padding(EdgeInsets(top: 12, bottom: 12, leading: 10, trailing: 10))
        }
        .frame(width: 260)
        .frame(maxHeight: .infinity)
        .background(Chrome.column)
    }

    private func designRow(_ design: KeyboardDesign) -> some View {
        let isSelected = editor.activeDesign.id == design.id
        return ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Chrome.accentWash : Color.clear)
            HStack(spacing: 6) {
                Text(design.name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? Chrome.accent : Chrome.textPrimary)
                Spacer()
                Text("\(design.rowCount)×\(design.colCount)")
                    .font(.system(size: 11))
                    .foregroundColor(Chrome.textTertiary)
            }
            .padding(EdgeInsets(top: 6, bottom: 6, leading: 8, trailing: 8))
        }
        .onTapGesture { selectDesign(design) }
    }

    private var matrixSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Matrix GPIO")
            Text("Rows: " + draft.matrix.rows.map(String.init).joined(separator: ", "))
                .font(.system(size: 11))
                .foregroundColor(Chrome.textSecondary)
            Text("Cols: " + draft.matrix.cols.map(String.init).joined(separator: ", "))
                .font(.system(size: 11))
                .foregroundColor(Chrome.textSecondary)
            Toggle("Columns are driven", isOn: colsAreDrivenBinding)
                .toggleStyle(.checkbox)
        }
    }

    private var colsAreDrivenBinding: Binding<Bool> {
        Binding(
            get: { draft.matrix.colsAreDriven != 0 },
            set: { draft.matrix.colsAreDriven = $0 ? 1 : 0 }
        )
    }
}

/// DSN rail mode's Inspector: Save/Duplicate/Delete for the design
/// currently open in the grid editor.
struct DesignInspectorView: View {
    var draft: KeyboardDesign
    var isExistingDesign: Bool
    var save: () -> Void
    var duplicate: () -> Void
    var delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Design actions")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Chrome.textPrimary)
            Text("\(draft.rowCount) rows · \(draft.colCount) cols · \(draft.name) matrix")
                .font(.system(size: 12))
                .foregroundColor(Chrome.textSecondary)
            Divider()
            InspectorButton(label: "Save Design", isPrimary: true, action: save)
            InspectorButton(label: "Duplicate…", action: duplicate)
            InspectorButton(label: "Delete", isDestructive: true, isEnabled: isExistingDesign, action: delete)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 300)
        .frame(maxHeight: .infinity)
        .background(Chrome.column)
    }
}
