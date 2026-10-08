import MetalUI

/// MACROS mode's step-editor inspector: Step / Macro / Timing tabs over the
/// open macro (`editor.currentMacro`), 248 wide, the tab content scrolling.
/// (`MacroInspectorTab` lives in `Model/MacroUITypes.swift`.)
///
/// Every field writes back through `editor.updateMacro(_:)`, the entry point
/// `EditorState`'s own step edits use, so an edit here marks the document dirty
/// like any other.
struct MacroInspectorView: Component {
    let editor: EditorState

    var content: some ElementGroup {
        pane {
            let editor = editor
            Column(gap: Pixels(14)) {
                // A segmented picker over the shared `editor.macroInspectorTab`
                // (Test run sets it too), where the previous build hand-built a
                // row of fake tab buttons (§2.2 W7).
                Picker("", selection: Binding(get: { editor.macroInspectorTab },
                                              set: { editor.macroInspectorTab = $0 })) {
                    for tab in MacroInspectorTab.allCases {
                        Text(tab.label).tag(tab)
                    }
                }
                .accessibilityLabel("Inspector tab")
                // The key chooser's menu, the repeat block's nested list and its
                // nested editor can run past the column's height.
                ScrollView(.vertical) {
                    Column(gap: Pixels(14)) {
                        tabContent
                    }
                    .alignItems(.stretch)
                }
                .frame(maxWidth: Pixels(.infinity), minHeight: Pixels(0), maxHeight: Pixels(.infinity))
            }
            .alignItems(.stretch)
            .padding(Insets.symmetric(horizontal: 15, vertical: 14))
            .frame(minWidth: Pixels(248), maxWidth: Pixels(248), maxHeight: Pixels(.infinity), alignment: .top)
            .background(Chrome.column)
        }
    }

    @ElementBuilder
    private var tabContent: some ElementGroup {
        if let macro = editor.currentMacro {
            switch editor.macroInspectorTab {
            case .step: stepTab(macro: macro)
            case .macro: macroTab(macro: macro)
            case .timing: timingTab(macro: macro)
            }
        }
    }

    // MARK: Step tab

    @ElementBuilder
    private func stepTab(macro: MacroDefinition) -> some ElementGroup {
        if let index = editor.selectedStepIndex, macro.steps.indices.contains(index) {
            let editor = editor
            // Keyed by the selection, so the repeat-block editor's own state
            // (which nested step is open) starts fresh for each step.
            MacroStepEditor(step: macro.steps[index], maxLayerIndex: editor.maxAssignableLayerIndex,
                            theme: editor.activeTheme) { newStep in
                guard var updated = editor.currentMacro, updated.steps.indices.contains(index) else { return }
                updated.steps[index] = newStep
                editor.updateMacro(updated)
            }
            .id("step-\(index)")
            InspectorButton(label: "Delete step", isDestructive: true) {
                editor.deleteStep(at: index)
            }
        } else {
            InspectorNote(text: "Select a step to edit it.", size: 12)
        }
    }

    // MARK: Macro tab

    private func macroTab(macro: MacroDefinition) -> some Element {
        let editor = editor
        let name = Binding<String>(
            get: { editor.currentMacro?.name ?? "" },
            set: { newValue in
                guard var updated = editor.currentMacro else { return }
                updated.name = newValue
                editor.updateMacro(updated)
            }
        )
        // `MacroLibraryRow`'s bound-cell lookup, so the library and this
        // summary never disagree about where a macro is bound.
        let row = MacroLibraryRow(macro: macro, document: editor.document)
        return Column(gap: Pixels(14)) {
            InspectorField(title: "Name") {
                TextField("Macro name", text: name)
                    .font(.system(size: 13))
            }
            InspectorField(title: "Bound key", spacing: 4) {
                Text(row.isBound ? "\(row.layerLabel) · \(row.triggerLabel)" : "Unbound")
                    .font(.system(size: 12))
                    .foregroundColor(Chrome.textSecondary)
            }
        }
        .alignItems(.stretch)
    }

    // MARK: Timing tab

    private func timingTab(macro: MacroDefinition) -> some Element {
        Column(gap: Pixels(14)) {
            InspectorField(title: "Estimated duration", spacing: 4) {
                Text(macro.estimatedDurationLabel)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Chrome.textPrimary)
            }
            InspectorField(title: "Per step") {
                for step in macro.steps {
                    TimingRow(step: step)
                }
            }
            InspectorNote(text: "Test run estimates timing only. It doesn't send keystrokes.")
        }
        .alignItems(.stretch)
    }
}

/// A section header over its content, `spacing` apart, full width.
struct InspectorField<Body: ElementGroup>: Component {
    var title: String
    var spacing: Float = 6
    var body: Body

    init(title: String, spacing: Float = 6, @ElementBuilder body: () -> Body) {
        self.title = title
        self.spacing = spacing
        self.body = body()
    }

    var content: some ElementGroup {
        Column(gap: Pixels(spacing)) {
            SectionHeader(title: title)
            body
        }
        .alignItems(.stretch)
    }
}

/// Tertiary explanatory text in the inspector.
struct InspectorNote: Component {
    var text: String
    var size: Double = 11
    var color: Color = Chrome.textTertiary

    var content: some ElementGroup {
        Text(text)
            .font(.system(size: size))
            .foregroundColor(color)
    }
}

/// A slider's value readout ("40 ms", "12 ms/char", "3×").
struct ValueReadout: Component {
    var text: String

    var content: some ElementGroup {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(Chrome.textTertiary)
    }
}

/// One Timing-tab row: the step's payload and its estimated duration.
struct TimingRow: Component {
    var step: MacroStep

    var content: some ElementGroup {
        Row(gap: Pixels(4)) {
            Text(step.payloadSummary)
                .font(.system(size: 11))
                .foregroundColor(Chrome.textSecondary)
            Spacer()
            Text("\(step.estimatedDurationMs) ms")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Chrome.textTertiary)
        }
    }
}

/// An `Int` millisecond value as the `Double` a `Slider` takes, written back
/// through `MacroStep.quantizedToTick` (the board ticks every 10 ms and rounds
/// every hold, delay and per-character pause up to the next tick, so a value
/// in between is never delivered as typed).
enum SliderAdapter {
    @MainActor
    static func milliseconds(_ value: Int, write: @escaping @MainActor (Int) -> Void) -> Binding<Double> {
        Binding(get: { Double(value) },
                set: { write(MacroStep.quantizedToTick(Int($0.rounded()))) })
    }

    @MainActor
    static func count(_ value: Int, write: @escaping @MainActor (Int) -> Void) -> Binding<Double> {
        Binding(get: { Double(value) }, set: { write(Int($0.rounded())) })
    }
}

/// The Step tab's per-type controls, one case per `MacroStep`. `update`
/// receives the whole replacement step; the caller splices it into the open
/// macro (or, inside a repeat block, into the block's steps).
///
/// Nothing here offers a "Paste all at once" text delivery: the firmware can
/// only send keystrokes (`TextDelivery` stays in the model so an existing file
/// loads losslessly).
struct MacroStepEditor: Component {
    var step: MacroStep
    /// The highest layer a `.layer` step may target --
    /// `EditorState.maxAssignableLayerIndex`, the same clamp the KEY palette's
    /// MO/TG picker uses.
    var maxLayerIndex: Int
    /// The active keyboard theme, for a repeat block's nested ADD STEP badges.
    var theme: KeyboardTheme
    var update: @MainActor (MacroStep) -> Void

    var content: some ElementGroup {
        switch step {
        case .keystroke(let mods, let key, let holdMs):
            keystrokeEditor(mods: mods, key: key, holdMs: holdMs)
        case .text(let text, let delivery, let msPerChar):
            textEditor(text: text, delivery: delivery, msPerChar: msPerChar)
        case .delay(let ms):
            delayEditor(ms: ms)
        case .layer(let op, let n):
            layerEditor(op: op, n: n)
        case .repeatBlock(let count, let steps):
            // Type-erased: the block's editor holds `MacroStepEditor`s of its
            // own, and a recursive opaque type cannot be spelled.
            pane {
                RepeatBlockEditor(count: count, steps: steps, maxLayerIndex: maxLayerIndex, theme: theme, update: update)
            }
        case .raw:
            InspectorNote(text: "Unsupported step (kept on save)", size: 12)
        }
    }

    // MARK: Keystroke

    /// The key is a menu picker over every `KeyName`, each option titled with
    /// its group ("Letters — A"): a menu has no sections (gap MG-8), and the
    /// previous build's grouped chip rows in horizontal scrollers existed only
    /// because SwiftCrossUI's `Picker` printed raw values (§2.2 W16). The
    /// modifiers stay eight multi-select chips.
    private func keystrokeEditor(mods: [ModifierName], key: KeyName?, holdMs: Int) -> some Element {
        let update = update
        let keyBinding = Binding<KeyName?>(
            get: { key },
            set: { newKey in update(.keystroke(mods: mods, key: newKey, holdMs: holdMs)) }
        )
        let rows = stride(from: 0, to: ModifierName.allCases.count, by: 4).map {
            Array(ModifierName.allCases[$0..<min($0 + 4, ModifierName.allCases.count)])
        }
        return Column(gap: Pixels(14)) {
            InspectorField(title: "Key", spacing: 4) {
                Text(key?.displayLabel ?? "No key selected")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Chrome.textPrimary)
                Picker("", selection: keyBinding) {
                    for group in KeyName.allGroups {
                        for candidate in group.keys {
                            Text("\(group.title) — \(candidate.displayLabel)").tag(Optional(candidate))
                        }
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Key")
            }
            InspectorField(title: "Modifiers", spacing: 4) {
                Column(gap: Pixels(6)) {
                    for row in rows {
                        ModifierChipRow(mods: row, selected: mods) { mod in
                            var newMods = mods
                            if let existing = newMods.firstIndex(of: mod) {
                                newMods.remove(at: existing)
                            } else {
                                newMods.append(mod)
                            }
                            update(.keystroke(mods: newMods, key: key, holdMs: holdMs))
                        }
                    }
                }
                .alignItems(.flexStart)
            }
            InspectorField(title: "Hold", spacing: 4) {
                Slider(value: SliderAdapter.milliseconds(holdMs) { update(.keystroke(mods: mods, key: key, holdMs: $0)) },
                       in: 10...500, step: 10)
                ValueReadout(text: "\(holdMs) ms")
            }
        }
        .alignItems(.stretch)
    }

    // MARK: Text

    private func textEditor(text: String, delivery: TextDelivery, msPerChar: Int) -> some Element {
        let update = update
        return Column(gap: Pixels(14)) {
            InspectorField(title: "Text", spacing: 4) {
                TextEditor(text: Binding(get: { text },
                                         set: { update(.text($0, delivery: delivery, msPerChar: msPerChar)) }))
                    .textEditorStyle(.plain)
                    .font(.system(size: 12))
                    .editorChrome()
                    .frame(height: Pixels(80))
            }
            InspectorField(title: "Typing speed", spacing: 4) {
                Slider(value: SliderAdapter.milliseconds(msPerChar) { update(.text(text, delivery: delivery, msPerChar: $0)) },
                       in: 10...100, step: 10)
                ValueReadout(text: "\(msPerChar) ms/char")
            }
        }
        .alignItems(.stretch)
    }

    // MARK: Delay

    private func delayEditor(ms: Int) -> some ElementGroup {
        let update = update
        return InspectorField(title: "Delay", spacing: 4) {
            Slider(value: SliderAdapter.milliseconds(ms) { update(.delay(ms: $0)) }, in: 0...5000, step: 10)
            ValueReadout(text: "\(ms) ms")
        }
    }

    // MARK: Layer

    /// `MO(0)` is a dead step: the firmware treats layer 0 as always active,
    /// and a macro's momentary push only releases when the macro ends. `TG(0)`
    /// is a real state change and is not flagged.
    static func isDeadMomentaryZero(op: LayerOp, n: Int) -> Bool {
        op == .momentary && n == 0
    }

    private func layerEditor(op: LayerOp, n: Int) -> some Element {
        let update = update
        let opBinding = Binding<LayerOp>(get: { op }, set: { update(.layer(op: $0, n: n)) })
        let layerBinding = Binding<Int>(get: { n }, set: { update(.layer(op: op, n: $0)) })
        return Column(gap: Pixels(14)) {
            InspectorField(title: "Operation", spacing: 4) {
                Picker("", selection: opBinding) {
                    Text("Momentary").tag(LayerOp.momentary)
                    Text("Toggle").tag(LayerOp.toggle)
                }
                .accessibilityLabel("Operation")
            }
            InspectorField(title: "Layer", spacing: 4) {
                Picker("", selection: layerBinding) {
                    for index in 0...max(0, maxLayerIndex) {
                        Text("\(index)").tag(index)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Layer")
            }
            if Self.isDeadMomentaryZero(op: op, n: n) {
                InspectorNote(
                    text: "Momentary layer 0 does nothing — layer 0 is always active, and a macro's momentary push only releases when the macro ends. Pick Toggle, or a layer above 0.",
                    color: Chrome.dangerText)
            }
        }
        .alignItems(.stretch)
    }
}

/// One row of up to four modifier chips.
struct ModifierChipRow: Component {
    var mods: [ModifierName]
    var selected: [ModifierName]
    var toggle: @MainActor (ModifierName) -> Void

    var content: some ElementGroup {
        Row(gap: Pixels(6)) {
            for mod in mods {
                MacroChip(label: mod.displayLabel, isSelected: selected.contains(mod)) { [toggle] in toggle(mod) }
            }
        }
    }
}

/// A 36×22 chip: `chipBackground`, a 1-point `chipBorder` hairline, or a
/// 2-point accent ring while selected. A real `Button`.
struct MacroChip: Component {
    var label: String
    var isSelected: Bool
    var action: @MainActor () -> Void

    var content: some ElementGroup {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(Chrome.textPrimary)
                .frame(width: Pixels(36), height: Pixels(22))
        }
        .buttonStyle(.plain)
        .background(Chrome.chipBackground)
        .cornerRadius(Pixels(4))
        .border(isSelected ? Chrome.accent : Chrome.chipBorder, width: Pixels(isSelected ? 2 : 1))
    }
}

/// The Step tab's editor for a repeat block: the count, the steps inside it
/// (rows reused from the step list), a nested ADD STEP (no RPT: repeat blocks
/// do not nest -- the firmware's player has one loop counter), and, once a
/// nested step is opened, that step's own editor inline.
///
/// Self-contained: every edit hands the whole replacement `.repeatBlock` to
/// `update`, so no nested selection path is needed in `EditorState`.
struct RepeatBlockEditor: Component {
    var count: Int
    var steps: [MacroStep]
    var maxLayerIndex: Int
    /// The active keyboard theme, for the nested ADD STEP badges.
    var theme: KeyboardTheme
    var update: @MainActor (MacroStep) -> Void

    /// Which nested step is open below the list. Local UI state, written from
    /// input only.
    @State var editingIndex: Int? = nil

    var content: some ElementGroup {
        let update = update
        let count = count
        let steps = steps
        Column(gap: Pixels(14)) {
            InspectorField(title: "Repeat count", spacing: 4) {
                Slider(value: SliderAdapter.count(count) { update(.repeatBlock(count: $0, steps: steps)) },
                       in: 1...20, step: 1)
                ValueReadout(text: "\(count)×")
            }
            if let editingIndex, steps.indices.contains(editingIndex) {
                nestedEditor(index: editingIndex)
            } else {
                stepsList
                addStepSection
            }
        }
        .alignItems(.stretch)
    }

    private var stepsList: some ElementGroup {
        let noun = steps.count == 1 ? "step" : "steps"
        let editing = $editingIndex
        return InspectorField(title: "\(steps.count) \(noun) inside") {
            if steps.isEmpty {
                InspectorNote(text: "No steps yet -- add one below.")
            } else {
                for index in steps.indices {
                    MacroStepRowView(
                        step: steps[index],
                        index: index,
                        isSelected: false,
                        onSelect: { editing.wrappedValue = index },
                        onMoveUp: { [self] in moveNested(from: index, to: index - 1) },
                        onMoveDown: { [self] in moveNested(from: index, to: index + 1) },
                        onDelete: { [self] in deleteNested(at: index) }
                    )
                }
            }
        }
    }

    private var addStepSection: some ElementGroup {
        let editing = $editingIndex
        let update = update
        let count = count
        let steps = steps
        return InspectorField(title: "Add step") {
            for type in MacroStepType.available(insideRepeatBlock: true) {
                MacroStepTypeRow(type: type, theme: theme) {
                    var newSteps = steps
                    newSteps.append(type.makeStep())
                    update(.repeatBlock(count: count, steps: newSteps))
                    editing.wrappedValue = newSteps.count - 1
                }
            }
        }
    }

    private func nestedEditor(index: Int) -> some Element {
        let editing = $editingIndex
        let update = update
        let count = count
        let steps = steps
        return Column(gap: Pixels(10)) {
            Row(gap: Pixels(4)) {
                SectionHeader(title: "Step \(index + 1) of \(steps.count)")
                Spacer()
                Button {
                    editing.wrappedValue = nil
                } label: {
                    Text("Back to list")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Chrome.accent)
                }
                .buttonStyle(.plain)
            }
            .alignItems(.center)
            MacroStepEditor(step: steps[index], maxLayerIndex: maxLayerIndex, theme: theme) { newStep in
                guard steps.indices.contains(index) else { return }
                var newSteps = steps
                newSteps[index] = newStep
                update(.repeatBlock(count: count, steps: newSteps))
            }
            InspectorButton(label: "Delete step", isDestructive: true) { [self] in
                deleteNested(at: index)
            }
        }
        .alignItems(.stretch)
    }

    private func moveNested(from source: Int, to destination: Int) {
        guard steps.indices.contains(source), steps.indices.contains(destination) else { return }
        var newSteps = steps
        let step = newSteps.remove(at: source)
        newSteps.insert(step, at: destination)
        update(.repeatBlock(count: count, steps: newSteps))
    }

    private func deleteNested(at index: Int) {
        guard steps.indices.contains(index) else { return }
        var newSteps = steps
        newSteps.remove(at: index)
        update(.repeatBlock(count: count, steps: newSteps))
        $editingIndex.wrappedValue = nil
    }
}
