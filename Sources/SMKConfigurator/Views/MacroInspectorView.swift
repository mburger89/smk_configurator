import Foundation
import SwiftCrossUI

/// The three tabs of MACROS mode's step-editor Inspector -- Step (the
/// selected step's own fields), Macro (name + where it's bound), Timing
/// (estimated duration, per step). `CaseIterable`'s declaration order is
/// the design order the tab row renders in and
/// `MacroEditingTests.inspectorTabs()` pins.
enum MacroInspectorTab: String, CaseIterable, Identifiable, Hashable {
    case step, macro, timing

    var id: String { rawValue }

    var label: String {
        switch self {
        case .step: return "Step"
        case .macro: return "Macro"
        case .timing: return "Timing"
        }
    }
}

/// MACROS mode's step-editor Inspector column: Step / Macro / Timing tabs
/// over whichever macro is open (`editor.currentMacro`). The tab row
/// mirrors `KeyInspectorView`'s idiom (`KeyModeViews.swift`) -- a `ForEach`
/// of sibling `TapTarget`s, not a segmented control, since a single
/// `TapTarget`'s content closure cannot branch (`UIStyle.swift:98`).
///
/// Every field writes back through `editor.updateMacro(_:)` -- the same
/// entry point `EditorState`'s own step-mutation methods use -- so an edit
/// here marks the document dirty exactly like any other document change.
struct MacroInspectorView: View {
    @Environment(EditorState.self) var editor
    @Environment(\.colorScheme) private var colorScheme
    private var chrome: Chrome { Chrome(scheme: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            tabRow
            // A plain `Spacer`-terminated `VStack` was enough back when
            // every tab's content was a few short fields, but the keystroke
            // key chooser and the repeat block's nested step list can both
            // run well past the column's own height (a grouped key palette
            // in particular -- see `MacroKeyChooserView`), so this now
            // scrolls rather than silently clipping or forcing the window
            // taller. Same idea as `PaletteDrawerView`'s own vertical
            // `ScrollView` for the same reason.
            ScrollView(.vertical) {
                content
            }
        }
        .padding(EdgeInsets(top: 14, bottom: 14, leading: 15, trailing: 15))
        .frame(width: 248)
        .frame(maxHeight: .infinity)
        .background(chrome.column)
    }

    private var tabRow: some View {
        HStack(spacing: 6) {
            ForEach(MacroInspectorTab.allCases) { candidate in
                TapTarget(
                    background: candidate == editor.macroInspectorTab ? chrome.accent : chrome.pillBackground,
                    cornerRadius: 6,
                    action: { editor.macroInspectorTab = candidate }
                ) {
                    Text(candidate.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(candidate == editor.macroInspectorTab ? .white : chrome.textPrimary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 28)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let macro = editor.currentMacro {
            switch editor.macroInspectorTab {
            case .step: stepTab(macro: macro)
            case .macro: macroTab(macro: macro)
            case .timing: timingTab(macro: macro)
            }
        } else {
            EmptyView()
        }
    }

    // MARK: - Step tab

    @ViewBuilder
    private func stepTab(macro: MacroDefinition) -> some View {
        if let index = editor.selectedStepIndex, macro.steps.indices.contains(index) {
            VStack(alignment: .leading, spacing: 14) {
                MacroStepEditorView(
                    step: macro.steps[index],
                    chrome: chrome,
                    maxLayerIndex: editor.maxAssignableLayerIndex
                ) { newStep in
                    var updated = macro
                    updated.steps[index] = newStep
                    editor.updateMacro(updated)
                }
                InspectorButton(label: "Delete step", isDestructive: true) {
                    editor.deleteStep(at: index)
                }
            }
        } else {
            Text("Select a step to edit it.")
                .font(.system(size: 12))
                .foregroundColor(chrome.textTertiary)
        }
    }

    // MARK: - Macro tab

    private func macroTab(macro: MacroDefinition) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: "Name")
                TextField("Macro name", text: nameBinding(for: macro))
                    .font(.system(size: 13))
            }
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(title: "Bound key")
                Text(boundKeySummary(for: macro))
                    .font(.system(size: 12))
                    .foregroundColor(chrome.textSecondary)
            }
        }
    }

    private func nameBinding(for macro: MacroDefinition) -> Binding<String> {
        Binding(
            get: { macro.name },
            set: { newValue in
                var updated = macro
                updated.name = newValue
                editor.updateMacro(updated)
            }
        )
    }

    /// Reuses `MacroLibraryRow`'s bound-cell lookup rather than re-deriving
    /// it -- the library table and this summary must never disagree about
    /// where a macro is bound.
    private func boundKeySummary(for macro: MacroDefinition) -> String {
        let row = MacroLibraryRow(macro: macro, document: editor.document)
        return row.isBound ? "\(row.layerLabel) · \(row.triggerLabel)" : "Unbound"
    }

    // MARK: - Timing tab

    private func timingTab(macro: MacroDefinition) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(title: "Estimated duration")
                Text(macro.estimatedDurationLabel)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(chrome.textPrimary)
            }
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: "Per step")
                ForEach(macro.steps.indices, id: \.self) { index in
                    HStack {
                        Text(macro.steps[index].payloadSummary)
                            .font(.system(size: 11))
                            .foregroundColor(chrome.textSecondary)
                        Spacer(minLength: 4)
                        Text("\(macro.steps[index].estimatedDurationMs) ms")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(chrome.textTertiary)
                    }
                }
            }
            Text("Test run estimates timing only. It doesn't send keystrokes.")
                .font(.system(size: 11))
                .foregroundColor(chrome.textTertiary)
        }
    }
}

/// Per-step editing controls for the Step tab, one `switch` case per
/// `MacroStep`. `update` receives the whole replacement step; the caller
/// (`MacroInspectorView.stepTab`) splices it back into the open macro and
/// calls `editor.updateMacro(_:)`, since only `EditorState` mutates the
/// document -- this view stays a pure function of `step`.
///
/// Uses the native controls `Slider`/`Picker`/`TextEditor`/`Toggle`
/// (`.switch` style, i.e. `ToggleSwitch`) rather than inventing custom
/// controls, per the design spec's "`Slider`, `TextEditor`, `Picker`, and
/// `ToggleSwitch` all exist natively, so the inspector is unaffected."
/// `ToggleSwitch` itself is package-internal to SwiftCrossUI (see
/// `Toggle.swift`); the public surface is `Toggle(_:isOn:).toggleStyle(.switch)`.
/// There is no boolean field on any `MacroStep` case for a "repeat while
/// held" concept the plan mentions but the model (`Model/Macro.swift`)
/// never grew -- adding an inert toggle would violate this feature's own
/// C4 contract ("nothing in the UI claims a capability the build does not
/// have"), so the toggle is wired to a real field instead: a text step's
/// delivery mode.
///
/// The keystroke case's key/modifier choosers (`MacroKeyChooserView`,
/// `MacroModifierChooserView`, below) are the one exception to "native
/// controls only": `KeyName` is several hundred cases, and a `Picker` shows
/// each option as flat `"\(value)"` text (see `layerOpLabels`'s label table
/// a few cases down for the same limitation), so a flat `Picker` over it
/// would be unusable. These reuse this codebase's other established custom
/// control -- the hand-rolled `ZStack` + `onTapGesture` chip
/// (`PaletteChip`/`KeyCapView`/`DesignCellView`, see `TapTarget`'s doc
/// comment in `UIStyle.swift`) -- grouped the same way `PaletteDrawerView`
/// groups the identical `KeyName.allGroups` vocabulary for KEY mode's
/// palette, rather than inventing a third taxonomy.
private struct MacroStepEditorView: View {
    var step: MacroStep
    var chrome: Chrome
    /// The highest layer index a `.layer` step can legally target --
    /// `EditorState.maxAssignableLayerIndex`, the same clamp the KEY-mode
    /// palette drawer's `mo:`/`tg:` layer picker already uses
    /// (`PaletteDrawerView.layerPickerGroup`). Offering the full firmware
    /// ceiling (`EditorState.maxLayerCount`, 16) instead would let a macro
    /// target a layer the open document doesn't have -- a step that can
    /// never fire, same failure mode that comment documents for `mo:`/`tg:`.
    var maxLayerIndex: Int
    var update: (MacroStep) -> Void

    var body: some View {
        switch step {
        case .keystroke(let mods, let key, let holdMs):
            keystrokeEditor(mods: mods, key: key, holdMs: holdMs)
        case .text(let s, let delivery, let msPerChar):
            textStepEditor(text: s, delivery: delivery, msPerChar: msPerChar)
        case .delay(let ms):
            delayEditor(ms: ms)
        case .layer(let op, let n):
            layerEditor(op: op, n: n)
        case .repeatBlock(let count, let steps):
            repeatEditor(count: count, steps: steps)
        case .raw:
            Text("Unsupported step (kept on save)")
                .font(.system(size: 12))
                .foregroundColor(chrome.textTertiary)
        }
    }

    // MARK: - Keystroke

    /// `Picker`'s built-in style would dump `KeyName`'s several hundred
    /// cases as a flat list -- unusable, per the design brief. Instead this
    /// mirrors `PaletteDrawerView`'s own solution to the identical problem:
    /// `KeyName.allGroups`' generated sections (Letters, Numbers, Editing &
    /// Punctuation, ...), each a horizontally-scrolling row of chips, inside
    /// one vertically-scrolling column (`MacroKeyChooserView`). Modifiers are
    /// a small, fixed 8-value multi-select (`MacroModifierChooserView`) --
    /// unlike the KEY-mode palette's `ModifierName` chips (which arm one
    /// modifier as its own standalone key press), a keystroke step's `mods`
    /// is a set that rides along with `key`, so tapping toggles membership
    /// rather than replacing a single selection.
    private func keystrokeEditor(mods: [ModifierName], key: KeyName?, holdMs: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(title: "Key")
                Text(key?.displayLabel ?? "No key selected")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(chrome.textPrimary)
                MacroKeyChooserView(
                    chrome: chrome,
                    selectedKey: key,
                    onSelect: { newKey in update(.keystroke(mods: mods, key: newKey, holdMs: holdMs)) }
                )
            }
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(title: "Modifiers")
                MacroModifierChooserView(
                    chrome: chrome,
                    selectedMods: mods,
                    onToggle: { mod in
                        var newMods = mods
                        if let existing = newMods.firstIndex(of: mod) {
                            newMods.remove(at: existing)
                        } else {
                            newMods.append(mod)
                        }
                        update(.keystroke(mods: newMods, key: key, holdMs: holdMs))
                    }
                )
            }
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(title: "Hold")
                Slider(
                    value: Binding(get: { holdMs }, set: { update(.keystroke(mods: mods, key: key, holdMs: $0)) }),
                    in: 10...500
                )
                Text("\(holdMs) ms")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(chrome.textTertiary)
            }
        }
    }

    // MARK: - Text

    private func textStepEditor(text: String, delivery: TextDelivery, msPerChar: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(title: "Text")
                TextEditor(
                    text: Binding(get: { text }, set: { update(.text($0, delivery: delivery, msPerChar: msPerChar)) })
                )
                .frame(height: 80)
            }
            Toggle(
                "Paste all at once",
                isOn: Binding(
                    get: { delivery == .paste },
                    set: { isPaste in
                        update(.text(text, delivery: isPaste ? .paste : .keystrokes, msPerChar: msPerChar))
                    }
                )
            )
            .toggleStyle(.switch)
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(title: "Typing speed")
                Slider(
                    value: Binding(
                        get: { msPerChar },
                        set: { update(.text(text, delivery: delivery, msPerChar: $0)) }
                    ),
                    in: 1...100
                )
                Text("\(msPerChar) ms/char")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(chrome.textTertiary)
            }
        }
    }

    // MARK: - Delay

    private func delayEditor(ms: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Delay")
            Slider(value: Binding(get: { ms }, set: { update(.delay(ms: $0)) }), in: 0...5000)
            Text("\(ms) ms")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(chrome.textTertiary)
        }
    }

    // MARK: - Layer

    /// `Picker`'s built-in style displays each option via `"\(value)"`, so
    /// `LayerOp` (whose raw values are the terse firmware tokens `mo`/`tg`)
    /// is offered as a small label table instead of the enum directly.
    private static let layerOpLabels: [(LayerOp, String)] = [
        (.momentary, "Momentary"), (.toggle, "Toggle"),
    ]

    private func layerEditor(op: LayerOp, n: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(title: "Operation")
                Picker(
                    of: Self.layerOpLabels.map(\.1),
                    selection: Binding(
                        get: { Self.layerOpLabels.first { $0.0 == op }?.1 },
                        set: { label in
                            guard let newOp = Self.layerOpLabels.first(where: { $0.1 == label })?.0 else { return }
                            update(.layer(op: newOp, n: n))
                        }
                    )
                )
            }
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(title: "Layer")
                Picker(
                    of: Array(0...max(0, maxLayerIndex)),
                    selection: Binding(
                        get: { n },
                        set: { newValue in
                            guard let newValue else { return }
                            update(.layer(op: op, n: newValue))
                        }
                    )
                )
            }
        }
    }

    // MARK: - Repeat block

    private func repeatEditor(count: Int, steps: [MacroStep]) -> some View {
        let noun = steps.count == 1 ? "step" : "steps"
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(title: "Repeat count")
                Slider(
                    value: Binding(get: { count }, set: { update(.repeatBlock(count: $0, steps: steps)) }),
                    in: 1...20
                )
                Text("\(count)×")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(chrome.textTertiary)
            }
            Text("\(steps.count) \(noun) inside")
                .font(.system(size: 11))
                .foregroundColor(chrome.textTertiary)
        }
    }
}

/// A vertically-scrolling column of `KeyName.allGroups`' sections, each a
/// horizontally-scrolling row of key chips -- the Step tab's key chooser.
/// Deliberately reuses the exact grouping `PaletteDrawerView` uses for KEY
/// mode's own palette (`KeyName.allGroups`) rather than inventing a second
/// taxonomy, and the exact chip visual (`PaletteChip`'s fill/border/selected
/// styling) reimplemented locally since `PaletteChip` itself is `private` to
/// `PaletteDrawerView.swift` and keyed off `editor.selectedToken` (the
/// KEY-mode "armed chip" concept), which has nothing to do with a macro
/// step's `key: KeyName?` field.
private struct MacroKeyChooserView: View {
    var chrome: Chrome
    var selectedKey: KeyName?
    var onSelect: (KeyName) -> Void

    /// Tall enough to show a couple of sections at once without the picker
    /// dominating the whole 248pt-wide inspector column -- the rest scrolls,
    /// same trade `PaletteDrawerView` makes for the full board palette.
    private static let height: Double = 168

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(KeyName.allGroups, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.title.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(chrome.textTertiary)
                        ScrollView(.horizontal) {
                            HStack(spacing: 6) {
                                ForEach(group.keys, id: \.self) { candidate in
                                    MacroChip(
                                        label: candidate.displayLabel,
                                        isSelected: selectedKey == candidate,
                                        chrome: chrome,
                                        action: { onSelect(candidate) }
                                    )
                                }
                            }
                        }
                        .frame(height: MacroChip.height + 6)
                    }
                }
            }
            .padding(6)
        }
        .frame(height: Self.height)
        .background(RoundedRectangle(cornerRadius: 6).fill(chrome.surface))
        .overlay {
            RoundedRectangle(cornerRadius: 6).stroke(chrome.dividerLight, style: StrokeStyle(width: 1))
        }
    }
}

/// The Step tab's modifier multi-select: all eight `ModifierName` cases as
/// toggleable chips, four to a row (fixed chunking, not a wrap layout --
/// this codebase has reverted `GeometryReader`-based wrap before). Every
/// chip whose modifier is in `selectedMods` reads as selected simultaneously,
/// unlike `MacroKeyChooserView` where exactly one (or none) is.
private struct MacroModifierChooserView: View {
    var chrome: Chrome
    var selectedMods: [ModifierName]
    var onToggle: (ModifierName) -> Void

    private static let columns = 4

    private var rows: [[ModifierName]] {
        stride(from: 0, to: ModifierName.allCases.count, by: Self.columns).map {
            Array(ModifierName.allCases[$0..<min($0 + Self.columns, ModifierName.allCases.count)])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: 6) {
                    ForEach(rows[rowIndex], id: \.self) { mod in
                        MacroChip(
                            label: mod.displayLabel,
                            isSelected: selectedMods.contains(mod),
                            chrome: chrome,
                            action: { onToggle(mod) }
                        )
                    }
                }
            }
        }
    }
}

/// One small chip shared by `MacroKeyChooserView` and
/// `MacroModifierChooserView` -- fill + label + a selected-state border,
/// built the same hand-rolled `ZStack` + `onTapGesture` way `PaletteChip`
/// (`PaletteDrawerView.swift`) is, rather than through `TapTarget`:
/// `TapTarget`'s border is always a fixed 1pt stroke (`UIStyle.swift`), and
/// the selected state here needs a heavier 2pt ring the same way
/// `PaletteChip`'s does.
private struct MacroChip: View {
    var label: String
    var isSelected: Bool
    var chrome: Chrome
    var action: () -> Void

    static let height: Double = 22

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(chrome.chipBackground)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(chrome.textPrimary)
        }
        .frame(width: 36, height: Self.height)
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? chrome.accent : chrome.chipBorder, style: StrokeStyle(width: isSelected ? 2 : 1))
        }
        .onTapGesture(perform: action)
    }
}
