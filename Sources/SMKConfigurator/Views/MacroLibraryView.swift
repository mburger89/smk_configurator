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
    @Environment(\.presentAlert) private var presentAlert
    private var chrome: Chrome { Chrome(scheme: colorScheme) }

    private var rows: [MacroLibraryRow] {
        editor.document.macroList.map { MacroLibraryRow(macro: $0, document: editor.document) }
    }

    /// Whole-set capacity warning (contract C2: "warns in the library row
    /// and status bar"). Deliberately the same reason surfaced by the step
    /// editor's SLOT section (`MacroBudget.blockReason`) so this is the one
    /// place in the app you don't have to be in the step editor to see it.
    /// `StatusBarView.swift` is out of scope this round -- see the report.
    private var capacityWarning: String? { editor.macroBudget.blockReason }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let capacityWarning {
                capacityBanner(capacityWarning)
            }
            columnHeader
            if rows.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(rows) { row in
                            MacroLibraryRowView(
                                row: row,
                                chrome: chrome,
                                isOverCapacity: capacityWarning != nil,
                                open: { editor.openMacro(id: row.id) },
                                delete: { confirmDelete(row) }
                            )
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
            ToolbarPill(label: "Record new", isEnabled: false, action: {})
                .help("Recording macros from the board isn't implemented yet.")

            ToolbarPill(label: "New macro", isAccent: true, action: editor.createMacro)
        }
        .padding(EdgeInsets(top: 16, bottom: 12, leading: 16, trailing: 16))
    }

    /// Delegates to `MacroBudget.headerSummaryLabel` rather than restating
    /// the "used of total · slots" phrasing here -- the step editor's SLOT
    /// section (`MacroEditorViews.swift`'s `summaryLabel(slot:)`) renders
    /// the same underlying numbers, so the wording judgment calls (what to
    /// say once layers are eating into the shared budget, what to say once
    /// they've exhausted it) live once in the model instead of twice in
    /// two views that could drift apart.
    private var budgetSummary: String { editor.macroBudget.headerSummaryLabel }

    /// Library-level half of contract C2's "warns in the library row and
    /// status bar" -- shown whenever the current macro set can't be
    /// flashed, using the same wording the step editor's SLOT section
    /// already shows (`MacroBudget.blockReason`), so the two never disagree.
    private func capacityBanner(_ reason: String) -> some View {
        Text(reason)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(chrome.dangerText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 6, bottom: 6, leading: 16, trailing: 16))
            .background(chrome.dangerText.opacity(0.12))
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

    /// Confirms before deleting, warning strongly when the macro is bound.
    /// Slot ids are reused (`KeymapDocument.nextMacroID` hands out the
    /// lowest free one), and `macro:N` tokens on keys are raw strings that
    /// nobody rewrites when a macro is deleted -- so the next macro created
    /// after this one can land back in this exact slot, and the bound key
    /// would then silently run *that* macro instead, with no error and no
    /// visual difference (`KeyCapView` resolves its label from whatever
    /// macro currently occupies the id at render time). That failure mode
    /// is silent and easy to miss, so the warning names the exact key/layer
    /// and spells out the consequence rather than a generic "are you sure".
    private func confirmDelete(_ row: MacroLibraryRow) {
        Task {
            if row.isBound {
                await presentAlert(
                    "\u{201c}\(row.name)\u{201d} is bound to \(row.triggerLabel) on \(row.layerLabel). "
                    + "Deleting it leaves that key pointing at an empty slot -- and if you create "
                    + "another macro afterward, it may silently reuse this slot and run on that key "
                    + "instead. Delete anyway?"
                ) {
                    Button("Delete Anyway") { editor.deleteMacro(id: row.id) }
                    Button("Cancel") {}
                }
            } else {
                await presentAlert("Delete \u{201c}\(row.name)\u{201d}?") {
                    Button("Delete") { editor.deleteMacro(id: row.id) }
                    Button("Cancel") {}
                }
            }
        }
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

/// One row in `MacroLibraryView`'s table: a raw `ZStack` (fill +
/// content) with `.onHover` chained directly in front of `.onTapGesture`
/// on that *same* view, plus a hover-revealed delete glyph as a sibling
/// in an outer, gesture-free `ZStack` -- exactly the shape
/// `KeyListColumnView.layerRow` uses (see its doc comment in
/// `KeyModeViews.swift`), and for the same reason: this row used to wrap
/// its content in `TapTarget` (whose `body` applies `.onTapGesture`
/// itself, `UIStyle.swift:110-120`) and chain `.onHover` onto that
/// `TapTarget` from outside. That put hover on a *different*,
/// outer-wrapping view from the tap gesture and broke click delivery to
/// the row entirely -- not just the nested trash glyph's. Building the
/// row directly out of `ZStack` keeps hover and tap on one view, the way
/// `layerRow`/`designRow`/`themeRow` all do; the delete glyph still can't
/// nest inside that same view (a second, independent tap target can't
/// live inside a first), so it stays a sibling under the outer `ZStack`,
/// which itself carries no gesture.
private struct MacroLibraryRowView: View {
    var row: MacroLibraryRow
    var chrome: Chrome
    /// Whole-set capacity overage (not something one row alone caused --
    /// slots/bytes are cumulative across the document, so there's no sound
    /// way to blame a single macro). Colors the byte count on every row
    /// uniformly rather than singling one out.
    var isOverCapacity: Bool
    var open: () -> Void
    var delete: () -> Void

    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .trailing) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(chrome.column)
                HStack(spacing: 0) {
                    cell(row.name, width: 240, weight: .semibold, color: chrome.textPrimary)
                    cell(row.triggerLabel, width: 130, color: row.isBound ? chrome.textSecondary : chrome.textTertiary)
                    cell("\(row.stepCount)", width: 90, color: chrome.textSecondary)
                    cell(row.layerLabel, width: 110, color: chrome.textSecondary)
                    cell("\(row.byteCount)", width: 90, color: isOverCapacity ? chrome.dangerText : chrome.textSecondary)
                    Spacer(minLength: 0)
                    // Reserved space so the hover-revealed trash glyph below
                    // never overlaps the BYTES column's text.
                    Color.clear.frame(width: 28)
                }
                .padding(EdgeInsets(top: 10, bottom: 10, leading: 16, trailing: 16))
            }
            .onHover { hovering in isHovered = hovering }
            .onTapGesture(perform: open)

            if isHovered {
                Text("🗑")
                    .font(.system(size: 11))
                    .foregroundColor(chrome.dangerText)
                    .padding(.trailing, 20)
                    .onTapGesture(perform: delete)
                    .help("Delete this macro")
            }
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
