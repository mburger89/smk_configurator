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
                                setEnabled: { editor.setMacroEnabled(id: row.id, $0) },
                                setCollection: { editor.setMacroCollection(id: row.id, $0) },
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
        Text("No macros yet. Create one to place it on a key.")
            .font(.system(size: 12))
            .foregroundColor(chrome.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

/// One row in `MacroLibraryView`'s table: a gesture-free outer `ZStack`
/// (fill + content) whose content `HStack` opens with the tappable
/// informational region -- a raw `ZStack` carrying `.onTapGesture` -- and
/// continues with the row's controls as *siblings* of it, never nested
/// inside it.
///
/// The nesting rule is not stylistic. This row used to wrap its content in
/// `TapTarget` (whose `body` applies `.onTapGesture` itself,
/// `UIStyle.swift:110-120`) and chain `.onHover` onto that `TapTarget` from
/// outside. That put hover on a *different*, outer-wrapping view from the
/// tap gesture and broke click delivery to the row entirely -- not just the
/// nested trash glyph's. Building the row directly out of `ZStack` keeps any
/// gesture and the view it belongs to as one, the way
/// `layerRow`/`designRow`/`themeRow` in `KeyModeViews.swift` all do, and a
/// second independent tap target (each control here is one) cannot live
/// inside the first, so every control is a sibling under an enclosing view
/// that carries no gesture of its own.
///
/// The tap-target `ZStack` therefore keeps exactly two direct children, and
/// neither is produced by an `if`. `disabledWarning` is a conditional second
/// line, so it goes inside `nameCell`'s `VStack` -- a grandchild by way of
/// the inner `HStack` -- rather than becoming a third child here.
///
/// The delete glyph used to be revealed on hover. It no longer is: with five
/// controls on a row, hover-revealing one of them is inconsistent, and the
/// `isHovered` state that drove it cannot be shared across sibling views
/// without reintroducing exactly the split-gesture bug above. Deletion is
/// still confirmed by an alert (`MacroLibraryView.confirmDelete`), so
/// nothing became easier to do by accident.
struct MacroLibraryRowView: View {
    var row: MacroLibraryRow
    var chrome: Chrome
    /// Whole-set capacity overage (not something one row alone caused --
    /// slots/bytes are cumulative across the document, so there's no sound
    /// way to blame a single macro). Colors the byte count on every row
    /// uniformly rather than singling one out.
    var isOverCapacity: Bool
    var open: () -> Void
    var setEnabled: (Bool) -> Void
    var setCollection: (String?) -> Void
    var duplicate: () -> Void
    var export: () -> Void
    var delete: () -> Void

    /// What the user has actually typed into `collectionField`, kept only
    /// long enough to stop the model's normalizer from rewriting the field
    /// underneath them -- see `collectionField` for why this is needed and
    /// `collectionText` for how it hands control back.
    @State private var collectionDraft: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(dimmed(chrome.column))
            HStack(spacing: 0) {
                // `.frame` on the tap target is load-bearing: `Color.clear`
                // -- the filler that makes the whole region tappable rather
                // than only the glyphs in it -- expands into whatever space
                // it is offered, so unpinned the tap target swallowed the
                // entire row, drifting the cells to the middle and flinging
                // the controls against the right edge, out from under their
                // own column headers.
                ZStack {
                    Color.clear
                    HStack(spacing: 0) {
                        nameCell
                        cell(row.triggerLabel, width: MacroLibraryColumn.trigger,
                             color: dimmed(row.isBound ? chrome.textSecondary : chrome.textTertiary))
                        cell("\(row.stepCount)", width: MacroLibraryColumn.steps,
                             color: dimmed(chrome.textSecondary))
                        cell("\(row.byteCount)", width: MacroLibraryColumn.bytes,
                             color: dimmed(isOverCapacity ? chrome.dangerText : chrome.textSecondary))
                    }
                }
                .frame(width: MacroLibraryColumn.informationalWidth)
                .onTapGesture(perform: open)

                collectionField
                Toggle("", isOn: Binding(get: { row.isEnabled }, set: setEnabled))
                    .toggleStyle(.switch)
                    .fixedSize()
                    // Pinned to the ON column like every other cell rather
                    // than left to whatever `.fixedSize()` happens to
                    // measure: this is the one column whose header width
                    // and content width would otherwise agree only by
                    // luck, which is the exact drift `MacroLibraryColumn`
                    // exists to rule out.
                    .frame(width: MacroLibraryColumn.enabled, alignment: .leading)
                    .help("Disabled macros aren't uploaded, and free their bytes.")
                glyph("⧉", action: duplicate, help: "Duplicate this macro")
                glyph("↑", action: export, help: "Export this macro to a file")
                glyph("🗑", action: delete, help: "Delete this macro", color: chrome.dangerText)
                Spacer(minLength: 0)
            }
            .padding(EdgeInsets(top: 10, bottom: 10, leading: 16, trailing: 16))
        }
        // Tall enough for the name plus the warning's two lines when there
        // is one; a 40 floor otherwise. A *minimum*, not a fixed height:
        // the warning case is 16 + 2 + 26 of text inside 20 of padding,
        // which lands exactly on 64, so a longer trigger label or a larger
        // system font would have nowhere to go under a strict frame and
        // would clip. `minHeight` lets the row grow instead.
        //
        // An ordinary row no longer actually renders at 40: `collectionField`'s
        // `TextField` has a natural height around 22, which inside this row's
        // 20pt of vertical padding lands near 42 -- past the floor, so the
        // floor doesn't bind and ordinary rows come out slightly taller than
        // 40. That is the intended effect of a floor rather than a ceiling
        // (the old strict frame this replaced was overflowing the control);
        // only the previous claim that ordinary rows "still read as 40" was
        // wrong.
        .frame(minHeight: row.disabledWarning == nil ? 40 : 64)
    }

    /// Fades one colour when the macro is disabled. swift-cross-ui has no
    /// view-level `.opacity` modifier -- only `Color` carries one -- so the
    /// row dims by fading each colour it draws rather than itself as a
    /// whole. Deliberately applied to the informational cells and the row
    /// fill only: the controls stay at full strength because they remain
    /// live (the toggle is how you turn the macro back on), and so does
    /// `disabledWarning`, which is the one thing on a dimmed row that must
    /// not be easy to overlook.
    private func dimmed(_ color: Color) -> Color {
        row.isEnabled ? color : color.opacity(0.55)
    }

    /// The MACRO column. The optional warning line lives here, stacked under
    /// the name, so that the `if` producing it sits two levels below the tap
    /// target's `ZStack` instead of becoming a third child of it -- see this
    /// type's doc comment.
    private var nameCell: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(dimmed(row.isEnabled ? chrome.textPrimary : chrome.textTertiary))
            if let warning = row.disabledWarning {
                // Two lines, not one: the sentence is longer than the
                // MACRO column and a single line truncates it mid-word, so
                // the part that says what to do about it ("until
                // re-enabled") is exactly the part that disappears.
                Text(warning)
                    .font(.system(size: 10))
                    .foregroundColor(chrome.dangerText)
                    .lineLimit(2)
            }
        }
        .frame(width: MacroLibraryColumn.name, alignment: .leading)
    }

    /// Free text, not a picker. A picker here could never work: its options
    /// came from `KeymapDocument.macroCollections`, which is *derived* from
    /// the collections macros are already in, so it could only ever offer a
    /// name that already existed -- and with no macro in any collection yet,
    /// there was nothing to offer at all. A derived set needs an entry point
    /// to gain its first member, and typing is it. (`macroCollections`
    /// itself stays: Task 9's header filter is its real consumer, where
    /// offering only the collections actually in use is exactly right.)
    ///
    /// Clearing the field hands `""` straight through --
    /// `EditorState.setMacroCollection(id:_:)` trims and folds blank to
    /// `nil`, so "ungrouped" is spelled `nil` here the same as everywhere
    /// else, with no sentinel string that a macro literally named after it
    /// could collide with.
    ///
    /// The raw string goes to the model on every keystroke (`textDidChange`
    /// in `AppKitBackend+TextField.swift`), but what is *displayed* comes
    /// from `collectionText`, not straight back off the model. That
    /// indirection is load-bearing: `TextField.commit` overwrites the
    /// widget's contents whenever the binding's value differs from them, and
    /// `setMacroCollection` trims. Bound naively, typing a space would
    /// store the trimmed string, see it differ from the "Work " in the
    /// field, and write "Work" back over it -- so every space would vanish
    /// as it was typed and a two-word collection name would be impossible
    /// to enter. The other `TextField`s in this app
    /// (`MacroInspectorView.nameBinding(for:)`,
    /// `DesignGridEditorView.nameBinding`) bind to setters that store
    /// verbatim, which is why none of them needed this.
    private var collectionField: some View {
        TextField(
            "Collection",
            text: Binding(
                get: { collectionText },
                set: { typed in
                    collectionDraft = typed
                    setCollection(typed)
                }
            )
        )
        .font(.system(size: 12))
        .frame(width: MacroLibraryColumn.collection)
    }

    /// The draft while it still describes what the model holds, the model
    /// otherwise. Comparing the draft's *trimmed* form to the stored value
    /// is what makes this self-healing rather than a second source of
    /// truth: whitespace the normalizer dropped is the one difference the
    /// draft is allowed to keep, so any other divergence -- a reload, an
    /// import, an edit from elsewhere -- means the model moved on its own
    /// and the draft is abandoned rather than shown over the top of it.
    ///
    /// Known limitation: `collectionDraft` is never cleared on focus loss,
    /// so trailing whitespace a user typed can remain on screen after the
    /// model has trimmed it away -- what is displayed can differ from what
    /// is stored, by whitespace only. It self-heals on the next real model
    /// change, so this is bounded and left alone rather than patched: there
    /// is no focus-loss hook in this view to clear the draft from.
    private var collectionText: String {
        Self.collectionText(draft: collectionDraft, stored: row.collection ?? "")
    }

    /// Pure form of the rule above, taking both strings directly so it is
    /// testable without a view: no draft shows the stored value; a draft
    /// that trims to the stored value shows the draft (this is the case
    /// that lets a user type trailing/interior spaces without the
    /// normalizer eating them mid-keystroke); anything else shows the
    /// stored value, because the model has moved on its own.
    nonisolated static func collectionText(draft: String?, stored: String) -> String {
        guard let draft, draft.trimmingCharacters(in: .whitespacesAndNewlines) == stored
        else { return stored }
        return draft
    }

    private func glyph(_ text: String, action: @escaping () -> Void,
                       help: String, color: Color? = nil) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(color ?? chrome.textSecondary)
            .padding(.trailing, 12)
            .onTapGesture(perform: action)
            .help(help)
    }

    private func cell(_ text: String, width: Double, weight: Font.Weight = .regular, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: weight))
            .foregroundColor(color)
            .frame(width: width, alignment: .leading)
    }
}
