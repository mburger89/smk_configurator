import Foundation

// The macro library's view-logic types, moved verbatim out of
// `Views/MacroLibraryView.swift` (port plan §4.3 item 3): the table's column
// widths, a row's derived strings, the search/collection filter and the
// collection picker's options. Pure values, tested without a view
// (`MacroLibraryFilterTests`), and compiled on every platform.

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

    /// The collection field's display rule (`MacroLibraryRowView`), taking
    /// both strings directly so it is testable without a view: no draft shows the stored value; a draft
    /// that trims to the stored value shows the draft (this is the case
    /// that lets a user type trailing/interior spaces without the
    /// normalizer eating them mid-keystroke); anything else shows the
    /// stored value, because the model has moved on its own.
    static func collectionText(draft: String?, stored: String) -> String {
        guard let draft, draft.trimmingCharacters(in: .whitespacesAndNewlines) == stored
        else { return stored }
        return draft
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
