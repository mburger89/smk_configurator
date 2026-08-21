import Foundation
import SwiftCrossUI

/// One row of the library table, with every displayed string derived up front
/// so the view itself stays declarative and the derivation stays testable.
struct MacroLibraryRow: Identifiable, Equatable {
    var id: Int
    var name: String
    var stepCount: Int
    var byteCount: Int
    var isBound: Bool
    var triggerLabel: String
    var layerLabel: String

    init(macro: MacroDefinition, document: KeymapDocument) {
        self.id = macro.id
        self.name = macro.name
        self.stepCount = macro.steps.count
        self.byteCount = macro.compiledSize

        // Find the first cell in any layer bound to this macro. A macro can
        // legitimately be bound more than once; the first is enough to answer
        // "can I reach this?", which is what the column is for.
        let token = ActionToken.macro(macro.id).canonicalString
        var found: (layer: Int, row: Int, col: Int)? = nil
        outer: for (l, layer) in document.layers.enumerated() {
            for (r, row) in layer.enumerated() {
                for (c, cell) in row.enumerated() where cell == token {
                    found = (l, r, c)
                    break outer
                }
            }
        }

        if let found {
            self.isBound = true
            self.triggerLabel = "R\(found.row)C\(found.col)"
            self.layerLabel = "Layer \(found.layer)"
        } else {
            self.isBound = false
            self.triggerLabel = "Unbound"
            self.layerLabel = "—"
        }
    }
}

/// MACROS rail mode's library: a table of every macro on the document, with
/// its trigger, step count, and byte cost -- the whole-body counterpart to
/// the step editor reached via `openMacro(id:)`. Built from the same
/// `Chrome`/`TapTarget`/`SectionHeader` primitives as `DesignListColumnView`/
/// `ThemeListColumnView`, just spanning the full body instead of one column.
struct MacroLibraryView: View {
    @Environment(EditorState.self) var editor
    @Environment(\.colorScheme) private var colorScheme
    private var chrome: Chrome { Chrome(scheme: colorScheme) }

    private var rows: [MacroLibraryRow] {
        editor.document.macroList.map { MacroLibraryRow(macro: $0, document: editor.document) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            columnHeader
            if rows.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(rows) { row in
                            MacroLibraryRowView(row: row, chrome: chrome) {
                                editor.openMacro(id: row.id)
                            }
                        }
                    }
                    .padding(EdgeInsets(top: 8, bottom: 12, leading: 16, trailing: 16))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(chrome.canvas)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Macros")
                .font(.system(size: 19, weight: .semibold))
                .foregroundColor(chrome.textPrimary)
            Text(budgetSummary)
                .font(.system(size: 11))
                .foregroundColor(chrome.textTertiary)
            Spacer()
            // Recording macros from the board is a later project -- this
            // stays disabled rather than implying a capability that doesn't
            // exist yet. See Task 13 for the final wording.
            TapTarget(background: chrome.pillBackground.opacity(0.4), cornerRadius: 6, action: {}) {
                Text("Record new")
                    .font(.system(size: 12))
                    .foregroundColor(chrome.textPrimary.opacity(0.4))
            }
            .padding(EdgeInsets(top: 5, bottom: 5, leading: 10, trailing: 10))
            .fixedSize()
            .help("Recording macros from the board isn't implemented yet.")

            TapTarget(background: chrome.accent, cornerRadius: 6, action: editor.createMacro) {
                Text("New macro")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(EdgeInsets(top: 5, bottom: 5, leading: 10, trailing: 10))
            .fixedSize()
        }
        .padding(EdgeInsets(top: 16, bottom: 12, leading: 16, trailing: 16))
    }

    private var budgetSummary: String {
        let budget = editor.macroBudget
        let estimate = budget.isEstimate ? " (estimated)" : ""
        return "\(budget.usedBytes) of \(budget.totalBytes) bytes · "
            + "\(budget.usedSlots) of \(budget.capacity.macroSlots) slots\(estimate)"
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            columnLabel("MACRO", width: 240)
            columnLabel("TRIGGER", width: 130)
            columnLabel("STEPS", width: 90)
            columnLabel("LAYER", width: 110)
            columnLabel("BYTES", width: 90)
        }
        .padding(EdgeInsets(top: 6, bottom: 6, leading: 16, trailing: 16))
    }

    private func columnLabel(_ title: String, width: Double) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(chrome.textTertiary)
            .frame(width: width, alignment: .leading)
    }

    private var emptyState: some View {
        Text("No macros yet. Create one to place it on a key.")
            .font(.system(size: 12))
            .foregroundColor(chrome.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

/// One tappable row in `MacroLibraryView`'s table. A separate view (rather
/// than a method on `MacroLibraryView`) so the `TapTarget` background can be
/// passed in as a value per the no-branching-inside-`TapTarget` rule
/// (`UIStyle.swift:98`).
private struct MacroLibraryRowView: View {
    var row: MacroLibraryRow
    var chrome: Chrome
    var open: () -> Void

    var body: some View {
        TapTarget(background: chrome.column, cornerRadius: 6, action: open) {
            HStack(spacing: 0) {
                cell(row.name, width: 240, weight: .semibold, color: chrome.textPrimary)
                cell(row.triggerLabel, width: 130, color: row.isBound ? chrome.textSecondary : chrome.textTertiary)
                cell("\(row.stepCount)", width: 90, color: chrome.textSecondary)
                cell(row.layerLabel, width: 110, color: chrome.textSecondary)
                cell("\(row.byteCount)", width: 90, color: chrome.textSecondary)
            }
            .padding(EdgeInsets(top: 10, bottom: 10, leading: 16, trailing: 16))
        }
        .frame(height: 40)
    }

    private func cell(_ text: String, width: Double, weight: Font.Weight = .regular, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: weight))
            .foregroundColor(color)
            .frame(width: width, alignment: .leading)
    }
}
