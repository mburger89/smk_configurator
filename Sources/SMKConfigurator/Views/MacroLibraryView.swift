import Foundation
import MetalUI

/// MACROS rail mode's library: a table of every macro on the document, with
/// its trigger, step count, byte cost, collection and enabled state -- the
/// whole-body counterpart to the step editor reached via `openMacro(id:)`.
/// (`MacroLibraryRow`, `MacroLibraryFilter`, `CollectionFilterOption` and
/// `MacroLibraryColumn` live in `Model/MacroLibraryModel.swift`.)
struct MacroLibraryView: Component {
    let editor: EditorState

    @Environment(\.fileDialogs) var dialogs

    @State var filter = MacroLibraryFilter()
    /// The row the delete alert asks about, and whether it is up.
    @State var rowToDelete: MacroLibraryRow? = nil
    @State var confirmingDelete = false

    /// Every row, before filtering -- what the empty states tell "no macros
    /// at all" from "none match the filter" with.
    private var allRows: [MacroLibraryRow] {
        editor.document.macroList.map { MacroLibraryRow(macro: $0, document: editor.document) }
    }

    var content: some ElementGroup {
        pane {
            let all = allRows
            let rows = filter.apply(to: all)
            // Whole-set capacity warning: the same reason the step editor's
            // SLOT section shows (`MacroBudget.blockReason`), so the two never
            // disagree.
            let warning = editor.macroBudget.blockReason
            Column {
                header
                if let warning {
                    capacityBanner(warning)
                }
                columnHeader
                if rows.isEmpty {
                    emptyState(hasMacros: !all.isEmpty)
                } else {
                    ScrollView(.vertical) {
                        Column(gap: Pixels(6)) {
                            for row in rows {
                                rowView(row, isOverCapacity: warning != nil)
                                    .id("macro-\(row.id)")
                            }
                        }
                        .alignItems(.stretch)
                        .padding(Insets.edges(top: 8, leading: 16, bottom: 12, trailing: 16))
                    }
                    .frame(maxWidth: Pixels(.infinity), minHeight: Pixels(0), maxHeight: Pixels(.infinity))
                }
            }
            .alignItems(.stretch)
            .frame(maxWidth: Pixels(.infinity), maxHeight: Pixels(.infinity), alignment: .top)
            .background(Chrome.canvas)
            .alert(deleteTitle, isPresented: $confirmingDelete, presenting: rowToDelete) { [editor] row in
                Button(row.isBound ? "Delete Anyway" : "Delete", role: .destructive) {
                    editor.deleteMacro(id: row.id)
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func rowView(_ row: MacroLibraryRow, isOverCapacity: Bool) -> MacroLibraryRowView {
        let editor = editor
        let filter = $filter
        let rowToDelete = $rowToDelete
        let confirming = $confirmingDelete
        let dialogs = dialogs
        return MacroLibraryRowView(
            row: row,
            isOverCapacity: isOverCapacity,
            open: { editor.openMacro(id: row.id) },
            setEnabled: { editor.setMacroEnabled(id: row.id, $0) },
            setCollection: { value in
                editor.setMacroCollection(id: row.id, value)
                // A row that stops matching the filter would vanish under the
                // cursor mid-edit; editing a collection drops the filter
                // instead.
                if filter.wrappedValue.collection != nil {
                    filter.wrappedValue.collection = nil
                }
            },
            duplicate: { _ = editor.duplicateMacro(id: row.id) },
            export: { Self.exportMacro(id: row.id, editor: editor, dialogs: dialogs) },
            delete: {
                rowToDelete.wrappedValue = row
                confirming.wrappedValue = true
            }
        )
    }

    // MARK: Header

    private var header: some Element {
        let editor = editor
        let dialogs = dialogs
        return Row(gap: Pixels(12)) {
            Text("Macros")
                .font(.system(size: 19, weight: .semibold))
                .foregroundColor(Chrome.textPrimary)
            Text(editor.macroBudget.headerSummaryLabel)
                .font(.system(size: 11))
                .foregroundColor(Chrome.textTertiary)
            Spacer()
            TextField("Search macros", text: $filter.query)
                .font(.system(size: 12))
                .frame(width: Pixels(180))
            collectionPicker
            // Recording macros from the board needs a device-to-host event
            // channel neither transport has; a real disabled button says so.
            PillButton(label: "Record new", isEnabled: false,
                       help: "Recording macros from the board isn't implemented yet.") {}
            PillButton(label: "Import") {
                Task { @MainActor in
                    guard let url = await KeymapFileActions.chooseFile(editor: editor, dialogs: dialogs) else { return }
                    _ = editor.importMacro(from: url)
                }
            }
            PillButton(label: "New macro", isAccent: true) { editor.createMacro() }
        }
        .alignItems(.center)
        .padding(Insets.edges(top: 16, leading: 16, bottom: 12, trailing: 16))
    }

    /// All, then every collection a macro is in. A stale selection (its last
    /// macro moved out, or the document was replaced) reads All
    /// (`CollectionFilterOption.selected(for:among:)`). Options are tagged by
    /// position: `CollectionFilterOption` is `Equatable` only, and a `Picker`
    /// tag must be `Hashable`.
    private var collectionPicker: some Element {
        let options = CollectionFilterOption.options(for: editor.document.macroCollections)
        let filter = $filter
        let selection = Binding<Int>(
            get: {
                let current = CollectionFilterOption.selected(for: filter.wrappedValue.collection, among: options)
                return options.firstIndex(of: current) ?? 0
            },
            set: { index in
                guard options.indices.contains(index) else { return }
                filter.wrappedValue.collection = options[index].filterValue
            }
        )
        return Picker("", selection: selection) {
            for (index, option) in options.enumerated() {
                Text(option.description).tag(index)
            }
        }
        .pickerStyle(.menu)
        .accessibilityLabel("Collection")
        .frame(width: Pixels(140))
    }

    private func capacityBanner(_ reason: String) -> some Element {
        Text(reason)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Chrome.dangerText)
            .padding(Insets.symmetric(horizontal: 16, vertical: 6))
            .frame(maxWidth: Pixels(.infinity), alignment: .leading)
            .background(Chrome.dangerText.opacity(0.12))
    }

    private var columnHeader: some Element {
        Row(gap: Pixels(0)) {
            columnLabel("MACRO", width: MacroLibraryColumn.name)
            columnLabel("TRIGGER", width: MacroLibraryColumn.trigger)
            columnLabel("STEPS", width: MacroLibraryColumn.steps)
            columnLabel("BYTES", width: MacroLibraryColumn.bytes)
            columnLabel("COLLECTION", width: MacroLibraryColumn.collection)
            columnLabel("ON", width: MacroLibraryColumn.enabled)
            Spacer()
        }
        // The rows sit 16 in from the canvas and pad their cells 16 more, so
        // the headings sit over their cells.
        .padding(Insets.symmetric(horizontal: 32, vertical: 6))
    }

    private func columnLabel(_ title: String, width: Double) -> some Element {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(Chrome.textTertiary)
            .frame(width: Pixels(Float(width)), alignment: .leading)
    }

    private func emptyState(hasMacros: Bool) -> some Element {
        Text(hasMacros
             ? "No macros match this search or collection."
             : "No macros yet. Create one to place it on a key.")
            .font(.system(size: 12))
            .foregroundColor(Chrome.textTertiary)
            .frame(maxWidth: Pixels(.infinity), maxHeight: Pixels(.infinity))
    }

    // MARK: Actions

    /// Slot ids are reused (`KeymapDocument.nextMacroID` hands out the lowest
    /// free one) and `macro:N` tokens on keys are never rewritten, so deleting
    /// a bound macro can silently re-point that key at the next macro created.
    /// The bound alert names the key and layer and says so.
    private var deleteTitle: String {
        guard let row = rowToDelete else { return "" }
        if row.isBound {
            return "\u{201c}\(row.name)\u{201d} is bound to \(row.triggerLabel) on \(row.layerLabel). "
                + "Deleting it leaves that key pointing at an empty slot -- and if you create "
                + "another macro afterward, it may silently reuse this slot and run on that key "
                + "instead. Delete anyway?"
        }
        return "Delete \u{201c}\(row.name)\u{201d}?"
    }

    /// One macro to a file the user picks (a save panel defaulting to
    /// "<name>.json"; MetalUI's dialogs take no title, gap MG-5). Export sits
    /// on the row because the table has no selection to name a macro with.
    private static func exportMacro(id: Int, editor: EditorState, dialogs: FileDialogs) {
        guard let macro = editor.document.macroList.first(where: { $0.id == id }) else { return }
        Task { @MainActor in
            guard let url = await KeymapFileActions.chooseDestination(
                editor: editor, dialogs: dialogs, defaultFilename: "\(macro.name).json"
            ) else { return }
            editor.exportMacro(macro, to: url)
        }
    }
}
