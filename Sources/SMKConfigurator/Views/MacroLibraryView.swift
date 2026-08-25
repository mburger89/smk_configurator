import Foundation
import SwiftCrossUI

/// The library table's column widths. Defined once because three separate
/// places have to agree on them -- `MacroLibraryView.columnHeader`, each
/// `MacroLibraryRowView` cell, and that row's tap-target width, which spans
/// the informational columns -- and a disagreement between any two of them
/// shows up as a table whose headings no longer sit over their own data.
enum MacroLibraryColumn {
    static let name: Double = 240
    static let trigger: Double = 130
    static let steps: Double = 90
    static let bytes: Double = 90
    static let collection: Double = 130
    static let enabled: Double = 60

    /// The span of the columns a row's tap target covers: everything up to
    /// the first control.
    static let informationalWidth = name + trigger + steps + bytes
}

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
    var isEnabled: Bool
    var collection: String?
    /// Name plus every step's text, lowercased so the filter can compare it
    /// against a lowercased query without either side re-folding case at the
    /// comparison. It is *not* a cache that survives keystrokes:
    /// `MacroLibraryView.rows` is a computed property, so every row -- and
    /// every `searchText` -- is rebuilt on each body evaluation regardless.
    var searchText: String
    /// Set only when a disabled macro still has a key bound to it -- that
    /// key compiles as a dead key (`compileKeymap` rewrites it), which is
    /// silent and easy to miss, so the row names it.
    var disabledWarning: String?

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

        self.isEnabled = macro.enabled
        self.collection = macro.collection
        self.searchText = ([macro.name] + macro.steps.map(\.searchableText))
            .joined(separator: " ")
            .lowercased()
        // Reuses the bound-key scan above rather than repeating it: `found`
        // has already answered "is any key pointing at this macro", which is
        // the same question the warning turns on.
        if !macro.enabled, found != nil {
            self.disabledWarning =
                "Disabled -- \(self.triggerLabel) on \(self.layerLabel) does nothing until re-enabled."
        } else {
            self.disabledWarning = nil
        }
    }
}

/// What the library header is currently filtering by. A plain value type
/// with a pure `apply(to:)` so the matching rules are testable without a
/// view, the same reason `MacroLibraryRow` derives its strings up front.
struct MacroLibraryFilter: Equatable {
    /// Free text matched against `MacroLibraryRow.searchText` -- the macro's
    /// name and every step's content, including steps nested inside a
    /// repeat block. Blank means "no search" rather than "match nothing".
    var query: String = ""

    /// `nil` means every collection. A named collection matches only macros
    /// assigned to it; ungrouped macros match no named collection.
    var collection: String? = nil

    func apply(to rows: [MacroLibraryRow]) -> [MacroLibraryRow] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return rows.filter { row in
            if let collection, row.collection != collection { return false }
            if needle.isEmpty { return true }
            return row.searchText.contains(needle)
        }
    }
}

/// One entry in the library header's collection filter. A dedicated type
/// rather than a reserved string: the picker's domain is built from
/// user-entered collection names, so any sentinel drawn from the same
/// `String` space collides with a macro that happens to use that exact
/// name. `_BuiltinPickerStyle` maps a selection back to a value by
/// `firstIndex(of:)` on the typed `[Value]` array itself -- only the
/// *rendered* row labels go through `"\($0)"` for display. That distinction
/// matters here because with the old `Value == String` sentinel design the
/// values *are* the labels, so a name collision in the value space is
/// exactly a `firstIndex(of:)` collision too: two rows read identically,
/// the first always wins, and a macro genuinely in a collection named the
/// same as the sentinel could never be filtered for. It would not
/// generalize to every `Value` type, though -- `CollectionFilterOption`
/// itself is the counterexample: `.all` and `.named("All")` render the same
/// label ("All") but remain distinct, `Equatable`-inequal values, so
/// `firstIndex(of:)` still resolves them correctly. `MacroLibraryRowView`
/// dropped a `"--"` sentinel from its collection field for the same reason
/// this type replaces the string sentinel here.
enum CollectionFilterOption: Equatable, CustomStringConvertible {
    case all
    case named(String)

    /// What `Picker` renders for this option -- `_BuiltinPickerStyle`
    /// derives each row's label from `"\(value)"`, so this conformance is
    /// not cosmetic: without it, `.named("Work")` would print as the
    /// enum's default `named("Work")` rather than `Work`.
    var description: String {
        switch self {
        case .all: return "All"
        case .named(let name): return name
        }
    }

    /// The full option list for a document's current collections. `.all`
    /// always leads and is not itself a collection, so it can never collide
    /// with one -- unlike the `"All"` string it replaces.
    static func options(for collections: [String]) -> [CollectionFilterOption] {
        [.all] + collections.map(CollectionFilterOption.named)
    }

    /// The option representing a filter's current `collection` value, for
    /// the picker's `get`.
    static func selected(for collection: String?) -> CollectionFilterOption {
        collection.map(CollectionFilterOption.named) ?? .all
    }

    /// Reconciled form of `selected(for:)`, for the picker's actual `get`:
    /// falls back to `.all` when `collection` names a collection no longer
    /// present in `options` -- the last macro in it moved out or was
    /// deleted, or the document was reloaded or imported wholesale, and
    /// `filter.collection` (`@State`, never itself reconciled against
    /// `editor.document.macroCollections`) is now stale.
    ///
    /// Left unreconciled, `filter.collection` still resolves to a `.named`
    /// value via the plain `selected(for:)` above, but `options` no longer
    /// contains it -- so `_BuiltinPickerStyle` computes `selectedIndex` by
    /// `firstIndex(of:)` and gets `nil`. The table correctly shows zero
    /// rows (nothing matches a collection nothing is in), but the picker
    /// renders with *nothing* selected rather than showing the stale name,
    /// which reads as a bug rather than the "no such collection" state it
    /// actually is. A pure static function, like `selected(for:)` itself,
    /// so this is testable without a view.
    static func selected(for collection: String?, among options: [CollectionFilterOption]) -> CollectionFilterOption {
        let candidate = selected(for: collection)
        return options.contains(candidate) ? candidate : .all
    }

    /// The `MacroLibraryFilter.collection` value this option resolves to
    /// once chosen, for the picker's `set`.
    var filterValue: String? {
        switch self {
        case .all: return nil
        case .named(let name): return name
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
    @Environment(\.chooseFileSaveDestination) private var chooseFileSaveDestination
    @Environment(\.chooseFile) private var chooseFile
    @State private var filter = MacroLibraryFilter()
    private var chrome: Chrome { Chrome(scheme: colorScheme) }

    /// Every row, before filtering -- the count the empty states below
    /// distinguish "no macros at all" from "none match the filter" with.
    private var allRows: [MacroLibraryRow] {
        editor.document.macroList.map { MacroLibraryRow(macro: $0, document: editor.document) }
    }

    private var rows: [MacroLibraryRow] { filter.apply(to: allRows) }

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
                                setEnabled: { editor.setMacroEnabled(id: row.id, $0) },
                                setCollection: { setCollection(for: row.id, to: $0) },
                                duplicate: { editor.duplicateMacro(id: row.id) },
                                export: { exportMacro(row) },
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
            TextField("Search macros", text: Binding(
                get: { filter.query },
                set: { filter.query = $0 }
            ))
            .frame(width: 180)

            // `.all` is not a collection, it is the absence of the filter --
            // `CollectionFilterOption` keeps that out of `String` space so a
            // collection literally named "All" still gets its own row. The
            // named options derive from what macros actually use, so an
            // emptied collection disappears from this picker on its own.
            Picker(
                of: CollectionFilterOption.options(for: editor.document.macroCollections),
                selection: Binding(
                    get: {
                        CollectionFilterOption.selected(
                            for: filter.collection,
                            among: CollectionFilterOption.options(for: editor.document.macroCollections)
                        )
                    },
                    set: { choice in
                        guard let choice else { return }
                        filter.collection = choice.filterValue
                    }
                )
            )
            .frame(width: 140)

            // Recording macros from the board is a later project -- this
            // stays disabled rather than implying a capability that doesn't
            // exist yet. See Task 13 for the final wording.
            ToolbarPill(label: "Record new", isEnabled: false, action: {})
                .help("Recording macros from the board isn't implemented yet.")
            ToolbarPill(label: "Import", action: importMacro)
            ToolbarPill(label: "New macro", isAccent: true, action: editor.createMacro)
        }
        .padding(EdgeInsets(top: 16, bottom: 12, leading: 16, trailing: 16))
    }

    /// `MacroLibraryRowView`'s collection field writes through on every
    /// keystroke, not on commit (see that view's doc comment on
    /// `collectionField` for why: SwiftCrossUI has no focus-loss hook, so
    /// committing only on submission would silently discard an edit when
    /// the user clicks away instead). With a collection filter active, the
    /// first keystroke that changes a row's collection away from the
    /// filtered one makes the row stop matching `filter`, `ForEach` tears
    /// its node down, and the field being typed into vanishes out from
    /// under the cursor.
    ///
    /// Fix: clear the active filter the moment a row's collection is
    /// edited. A visible row necessarily matches the current filter, so
    /// this is unconditional whenever a filter is active -- no need to
    /// check whether *this* edit is the one that would have broken the
    /// match. This is the predictable rule, not a workaround: editing a
    /// macro out of the collection you're filtering by drops the filter so
    /// you can see what you did, the same way clearing any other filter
    /// would reveal more rows rather than fewer.
    ///
    /// Two alternatives were rejected. Exempting the row being edited from
    /// the filter is architecturally awkward: the in-progress text lives in
    /// `collectionDraft`, `@State` private to `MacroLibraryRowView`, and
    /// this view -- which owns `filter` and runs the match -- cannot see
    /// it. Committing the edit on submission instead of per keystroke would
    /// dodge the problem, but SwiftCrossUI has no focus-loss hook to commit
    /// on, so a user who clicks away without pressing return would lose the
    /// edit entirely -- a worse failure than the one being fixed here.
    private func setCollection(for id: Int, to value: String?) {
        editor.setMacroCollection(id: id, value)
        if filter.collection != nil {
            filter.collection = nil
        }
    }

    private func importMacro() {
        Task {
            guard let url = await chooseFile(title: "Import macro JSON",
                                             allowSelectingFiles: true)
            else { return }
            editor.importMacro(from: url)
        }
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
            columnLabel("MACRO", width: MacroLibraryColumn.name)
            columnLabel("TRIGGER", width: MacroLibraryColumn.trigger)
            columnLabel("STEPS", width: MacroLibraryColumn.steps)
            columnLabel("BYTES", width: MacroLibraryColumn.bytes)
            columnLabel("COLLECTION", width: MacroLibraryColumn.collection)
            columnLabel("ON", width: MacroLibraryColumn.enabled)
        }
        .padding(EdgeInsets(top: 6, bottom: 6, leading: 16, trailing: 16))
    }

    /// Writes one macro to a file the user picks. Exports a single macro
    /// rather than the whole library because the library table has no
    /// selection concept to name one with otherwise -- this is the row's
    /// own action, which is why Export sits on the row while Import (which
    /// has nothing to act on) sits in the header.
    private func exportMacro(_ row: MacroLibraryRow) {
        Task {
            guard
                let macro = editor.document.macroList.first(where: { $0.id == row.id }),
                let url = await chooseFileSaveDestination(
                    title: "Export macro",
                    defaultFileName: "\(macro.name).json")
            else { return }
            editor.exportMacro(macro, to: url)
        }
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
        Text(allRows.isEmpty
             ? "No macros yet. Create one to place it on a key."
             : "No macros match this search or collection.")
            .font(.system(size: 12))
            .foregroundColor(chrome.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
