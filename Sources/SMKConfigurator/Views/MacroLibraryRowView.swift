import Foundation
import SwiftCrossUI

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
