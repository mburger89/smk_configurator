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
            content
            Spacer(minLength: 0)
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

    private func keystrokeEditor(mods: [ModifierName], key: KeyName?, holdMs: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(title: "Keys")
                Text(step.payloadSummary)
                    .font(.system(size: 13))
                    .foregroundColor(chrome.textPrimary)
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
