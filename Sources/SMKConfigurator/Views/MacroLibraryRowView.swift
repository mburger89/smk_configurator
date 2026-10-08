import MetalUI

/// One row in `MacroLibraryView`'s table: the informational cells (MACRO,
/// TRIGGER, STEPS, BYTES) as one plain `Button` that opens the macro, then the
/// row's controls -- the collection field, the enabled checkbox, and the
/// duplicate / export / delete glyph buttons -- all inside one row container.
///
/// The previous build had to keep every control a *sibling* of a hand-built
/// tap target (SwiftCrossUI could not nest one tap target in another), fill the
/// informational region with `Color.clear` to make it tappable, put each
/// glyph's tap gesture before its padding, and fade every colour by hand
/// because it had no view opacity (port plan §2.2 W4, W9, W10, W11). Here the
/// open button is sized by its cells, each glyph is a `Button` sized by its own
/// label with the spacing outside it, and a disabled macro's informational
/// cells take `.opacity(0.55)`. The controls stay at full strength (the
/// checkbox is how a macro is turned back on), and so does the disabled-and-bound
/// warning, the one thing on a dimmed row that must not be easy to overlook.
struct MacroLibraryRowView: Component {
    let row: MacroLibraryRow
    /// Whole-set capacity overage: slots and bytes are cumulative across the
    /// document, so no one macro is to blame; every row's byte count turns red.
    let isOverCapacity: Bool
    let open: @MainActor () -> Void
    let setEnabled: @MainActor (Bool) -> Void
    let setCollection: @MainActor (String?) -> Void
    let duplicate: @MainActor () -> Void
    let export: @MainActor () -> Void
    let delete: @MainActor () -> Void

    /// What the user has typed into the collection field, kept only long
    /// enough to stop the model's normaliser (which trims) from rewriting the
    /// field underneath them -- see `MacroLibraryRow.collectionText`.
    @State var collectionDraft: String? = nil

    /// A disabled macro's informational cells fade to 0.55.
    private var dim: Float { row.isEnabled ? 1 : 0.55 }

    var content: some ElementGroup {
        Row(gap: Pixels(0)) {
            informationalCells
            collectionField
            Box().frame(width: Pixels(8))
            enabledToggle
            Row(gap: Pixels(12)) {
                glyph("⧉", help: "Duplicate this macro", color: Chrome.textSecondary, action: duplicate)
                glyph("↑", help: "Export this macro to a file", color: Chrome.textSecondary, action: export)
                // A monochrome glyph: colour emoji ("🗑") are not drawn (gap MG-6).
                glyph("✕", help: "Delete this macro", color: Chrome.dangerText, action: delete)
            }
            .alignItems(.center)
            Spacer()
        }
        .alignItems(.center)
        .padding(Insets.symmetric(horizontal: 16, vertical: 10))
        // A floor, not a fixed height: the warning's two lines need 64, and a
        // longer label must be able to grow the row rather than clip.
        .frame(maxWidth: Pixels(.infinity), minHeight: Pixels(row.disabledWarning == nil ? 40 : 64))
        .background(Chrome.column)
        .cornerRadius(Pixels(6))
    }

    /// MACRO, TRIGGER, STEPS and BYTES -- one button spanning exactly
    /// `MacroLibraryColumn.informationalWidth`, so a click anywhere over them
    /// opens the macro and the controls keep their own columns.
    private var informationalCells: some Element {
        Button(action: open) {
            Row(gap: Pixels(0)) {
                nameCell
                cell(row.triggerLabel, width: MacroLibraryColumn.trigger,
                     color: row.isBound ? Chrome.textSecondary : Chrome.textTertiary)
                cell("\(row.stepCount)", width: MacroLibraryColumn.steps, color: Chrome.textSecondary)
                cell("\(row.byteCount)", width: MacroLibraryColumn.bytes,
                     color: isOverCapacity ? Chrome.dangerText : Chrome.textSecondary)
            }
            .alignItems(.center)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(row.name)")
    }

    /// The MACRO column: the name, and under it the disabled-and-bound warning
    /// (two lines: one truncates exactly the "until re-enabled" part).
    private var nameCell: some Element {
        Column(gap: Pixels(2)) {
            Text(row.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(row.isEnabled ? Chrome.textPrimary : Chrome.textTertiary)
                .opacity(dim)
            if let warning = row.disabledWarning {
                Text(warning)
                    .font(.system(size: 10))
                    .foregroundColor(Chrome.dangerText)
                    .lineLimit(2)
            }
        }
        .alignItems(.flexStart)
        .frame(width: Pixels(Float(MacroLibraryColumn.name)), alignment: .leading)
    }

    private func cell(_ text: String, width: Double, color: Color) -> some Element {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(color)
            .opacity(dim)
            .frame(width: Pixels(Float(width)), alignment: .leading)
    }

    /// Free text, not a picker: the collection set is derived from the
    /// collections macros are already in, so typing is the only way to start
    /// a new one. Every keystroke writes through (`EditorState.setMacroCollection`
    /// trims and folds blank to `nil`); what is displayed is
    /// `MacroLibraryRow.collectionText`, so a typed space survives the trim.
    private var collectionField: some Element {
        let draft = $collectionDraft
        let stored = row.collection ?? ""
        let setCollection = setCollection
        return TextField("Collection", text: Binding(
            get: { MacroLibraryRow.collectionText(draft: draft.wrappedValue, stored: stored) },
            set: { typed in
                draft.wrappedValue = typed
                setCollection(typed)
            }
        ))
        .font(.system(size: 12))
        .fieldChrome()
        // 8 short of the column, so the field's border clears the ON column.
        .frame(width: Pixels(Float(MacroLibraryColumn.collection) - 8))
    }

    /// The ON column: a checkbox (MetalUI has no switch style, gap MG-4),
    /// pinned to the column's width like every other cell. Titleless, so it
    /// keeps a 7-point trailing gap after the box (MG-18) and carries its own
    /// accessibility label.
    private var enabledToggle: some Element {
        let setEnabled = setEnabled
        return Toggle("", isOn: Binding(get: { row.isEnabled }, set: { setEnabled($0) }))
            .accessibilityLabel("Enabled")
            .help("Disabled macros aren't uploaded, and free their bytes.")
            .frame(width: Pixels(Float(MacroLibraryColumn.enabled)), alignment: .leading)
    }

    private func glyph(_ text: String, help: String, color: Color,
                       action: @escaping @MainActor () -> Void) -> some Element {
        Button(action: action) {
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(color)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
