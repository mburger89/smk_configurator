import Foundation
import SwiftCrossUI

/// The five entries in the ADD STEP palette. Separate from `MacroStep`
/// because the palette needs a stable, ordered, badge-coloured list, while
/// `MacroStep` is a value with payloads.
enum MacroStepType: String, CaseIterable, Identifiable, Hashable {
    case keystroke, text, delay, layer, repeatBlock

    var id: String { rawValue }

    var badge: String {
        switch self {
        case .keystroke: return "KEY"
        case .text: return "TXT"
        case .delay: return "DLY"
        case .layer: return "LYR"
        case .repeatBlock: return "RPT"
        }
    }

    var label: String {
        switch self {
        case .keystroke: return "Keystroke"
        case .text: return "Type text"
        case .delay: return "Delay"
        case .layer: return "Switch layer"
        case .repeatBlock: return "Repeat block"
        }
    }

    /// The badge fill, sourced from the same per-theme keycap roles
    /// `KeyCapView`/`KeyboardTheme.background(for:)` already use -- not a
    /// fixed literal, so the palette stays in sync with whichever theme is
    /// active instead of inventing a second, parallel color set. `nil`
    /// means the neutral pill background (`chrome.pillBackground`), used
    /// for Repeat block since it has no keycap role of its own.
    func badgeColor(theme: KeyboardTheme) -> Color? {
        switch self {
        case .keystroke: return theme.keyBackground.color
        case .text: return theme.emptyBackground.color
        case .delay: return theme.modifierBackground.color
        case .layer: return theme.layerBackground.color
        case .repeatBlock: return nil
        }
    }

    /// A new step of this type with the defaults the design shows.
    func makeStep() -> MacroStep {
        switch self {
        case .keystroke: return .keystroke(mods: [], key: .a, holdMs: 40)
        case .text: return .text("", delivery: .keystrokes, msPerChar: 12)
        case .delay: return .delay(ms: 100)
        case .layer: return .layer(op: .momentary, n: 1)
        case .repeatBlock: return .repeatBlock(count: 2, steps: [])
        }
    }

    /// Repeat blocks don't nest -- the firmware's future player uses a
    /// single loop counter, not a stack -- so RPT disappears from the
    /// palette while the selection is inside one.
    static func available(insideRepeatBlock: Bool) -> [MacroStepType] {
        insideRepeatBlock ? allCases.filter { $0 != .repeatBlock } : allCases
    }
}

/// The step editor's left column: tap a step type to insert it after the
/// current selection (`EditorState.insertStepAfterSelection(_:)`), see the
/// slot budget, and leave the editor. Built from the same `Chrome`/
/// `TapTarget`/`SectionHeader` primitives as `PaletteDrawerView`/
/// `DesignListColumnView`; tap-to-add rather than drag-and-drop, since
/// SwiftCrossUI has no drag gesture.
struct MacroStepPaletteView: View {
    @Environment(EditorState.self) var editor
    @Environment(\.colorScheme) private var colorScheme
    private var chrome: Chrome { Chrome(scheme: colorScheme) }

    /// Whether the current selection sits inside a repeat block -- controls
    /// whether RPT is offered (`MacroStepType.available(insideRepeatBlock:)`).
    /// The step editor doesn't yet track nested selection paths (that's the
    /// sequence view's concern, Task 11), so this is `false` until that
    /// lands; passed in rather than hardcoded so the call site is the one
    /// place that will need to change.
    var insideRepeatBlock: Bool = false

    /// The column's total width -- also the basis for `slotSection`'s fixed
    /// track width, since the two must not drift apart.
    static let width: Double = 212
    private static let outerPadding: Int = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            addStepSection
            captureSection
            slotSection
            Spacer(minLength: 0)
            TapTarget(background: chrome.pillBackground, cornerRadius: 6, action: editor.closeMacro) {
                Text("Back to library")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(chrome.textPrimary)
            }
            .frame(height: 30)
        }
        .padding(EdgeInsets(top: 14, bottom: 14, leading: Self.outerPadding, trailing: Self.outerPadding))
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .background(chrome.column)
    }

    private var addStepSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Add step")
            ForEach(MacroStepType.available(insideRepeatBlock: insideRepeatBlock)) { type in
                MacroStepTypeRow(type: type, chrome: chrome) {
                    editor.insertStepAfterSelection(type.makeStep())
                }
            }
        }
    }

    /// Recording macros from the board is a later project (sub-project 4 --
    /// no device→host event channel exists in either transport) -- this
    /// stays disabled rather than implying a capability that doesn't exist
    /// yet, per contract C4. Matches the library table's "Record new" button
    /// (`MacroLibraryView.header`). The helper line beneath the button is the
    /// honest replacement for the design handoff's "Captured events append as
    /// steps and keep their measured gaps." -- that line describes behaviour
    /// this build does not have.
    private var captureSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Capture")
            TapTarget(background: chrome.pillBackground.opacity(0.4), cornerRadius: 6, action: {}) {
                Text("Record from board")
                    .font(.system(size: 12))
                    .foregroundColor(chrome.textPrimary.opacity(0.4))
            }
            .frame(height: 30)
            .help("Recording macros from the board isn't implemented yet.")
            Text("Recording from the board isn't available yet.")
                .font(.system(size: 11))
                .foregroundColor(chrome.textTertiary)
        }
    }

    /// The column's content width (`Self.width` minus its own leading/trailing
    /// padding) -- the SLOT track's fixed total width. A plain constant
    /// rather than a `GeometryReader` measurement: this codebase already hit
    /// real `GeometryReader` fragility on the palette drawer's chip wrapping
    /// (a `proposedSize == .zero` window-min-size probe interaction that
    /// broke window resizing), so fixed-width layout is the established,
    /// safer pattern here wherever the width is known up front.
    private static let trackWidth: Double = width - 2 * Double(outerPadding)

    private var slotSection: some View {
        let budget = editor.macroBudget
        // `MacroDefinition.id` *is* the firmware slot number (see its doc
        // comment) and is the same number the canvas header's "macro:<id>"
        // line already shows -- reusing it here rather than a separately
        // computed list position keeps the two readouts from disagreeing.
        let slot = editor.currentMacro?.id ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Slot")
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(chrome.dividerLight)
                    .frame(width: Self.trackWidth, height: 5)
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(budget.canFlash ? chrome.accent : chrome.dangerText)
                    .frame(width: Self.trackWidth * budget.fillFraction, height: 5)
            }
            Text(budget.summaryLabel(slot: slot))
                .font(.system(size: 11))
                .foregroundColor(chrome.textTertiary)
            if let blockReason = budget.blockReason {
                Text(blockReason)
                    .font(.system(size: 11))
                    .foregroundColor(chrome.dangerText)
            }
        }
    }
}

/// One row in the ADD STEP palette: a 28pt colour badge plus a label. A
/// separate view (rather than a method on `MacroStepPaletteView`) so the
/// `TapTarget` background stays a value passed in, per the
/// no-branching-inside-`TapTarget` rule (`UIStyle.swift:98`).
private struct MacroStepTypeRow: View {
    var type: MacroStepType
    var chrome: Chrome
    var insert: () -> Void

    @Environment(EditorState.self) var editor

    var body: some View {
        TapTarget(background: chrome.chipBackground, cornerRadius: 6, action: insert) {
            HStack(spacing: 8) {
                badge
                Text(type.label)
                    .font(.system(size: 12))
                    .foregroundColor(chrome.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(EdgeInsets(top: 0, bottom: 0, leading: 8, trailing: 8))
        }
        .frame(height: 36)
    }

    private var badge: some View {
        let themeColor = type.badgeColor(theme: editor.activeTheme)
        let fill = themeColor ?? chrome.pillBackground
        let textColor = themeColor != nil ? editor.activeTheme.keyText.color : chrome.textPrimary
        return ZStack {
            RoundedRectangle(cornerRadius: 4).fill(fill)
            Text(type.badge)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(textColor)
        }
        .frame(width: 28, height: 28)
    }
}

/// The step editor's canvas header: the open macro's name, its metadata
/// line, and the right-aligned action buttons. Mirrors
/// `MacroLibraryView.header`'s spacing/typography so the library table and
/// the step editor read as one surface.
///
/// Takes no init parameters -- `ContentView` (Task 12) wires this in as a
/// bare `MacroCanvasHeaderView()`, so it reads `editor.currentMacro` itself
/// rather than being handed one. Renders nothing when there's no open macro;
/// that shouldn't happen in practice (`ContentView` only shows this while
/// `editor.macroWorkspace` is `.editor`), but a missing macro is safer to
/// render as empty than to force-unwrap.
///
/// "Save" returns to the library (`editor.closeMacro()`): macro edits are
/// already committed live via `editor.updateMacro(_:)` as they happen (see
/// Task 12's Step tab), unlike Designs/Themes' separate draft-then-Save
/// flow, so there is no pending edit for this button to flush -- it reads
/// as the primary "I'm done, take me back" action instead. "Test run" is a
/// real, working button -- unlike "Record from board"/"Record new", which
/// stay genuinely disabled because they need capabilities this build lacks,
/// walking the macro's steps and computing a timing trace needs nothing new:
/// `MacroInspectorView`'s Timing tab already renders `estimatedDurationMs`
/// per step. So "Test run" just switches the shared
/// `editor.macroInspectorTab` to `.timing`, where that trace -- and its
/// "doesn't send keystrokes" disclaimer -- live (see C4 in the design spec:
/// this is the one deferred-sounding control that has a genuine
/// implementation, not just an honest disabled state).
struct MacroCanvasHeaderView: View {
    @Environment(EditorState.self) var editor
    @Environment(\.colorScheme) private var colorScheme
    private var chrome: Chrome { Chrome(scheme: colorScheme) }

    var body: some View {
        if let macro = editor.currentMacro {
            header(for: macro)
        } else {
            EmptyView()
        }
    }

    private func header(for macro: MacroDefinition) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(macro.name)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(chrome.textPrimary)
                Text(macro.canvasSummary)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(chrome.textSecondary)
            }
            Spacer()
            TapTarget(background: chrome.pillBackground, cornerRadius: 6, action: {
                editor.macroInspectorTab = .timing
            }) {
                Text("Test run")
                    .font(.system(size: 12))
                    .foregroundColor(chrome.textPrimary)
            }
            .padding(EdgeInsets(top: 5, bottom: 5, leading: 10, trailing: 10))
            .fixedSize()
            .help("Walks the macro's steps and shows the timing trace in the inspector. Doesn't send keystrokes.")
            TapTarget(background: chrome.accent, cornerRadius: 6, action: editor.closeMacro) {
                Text("Save")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(EdgeInsets(top: 5, bottom: 5, leading: 10, trailing: 10))
            .fixedSize()
        }
        .padding(EdgeInsets(top: 16, bottom: 12, leading: 16, trailing: 16))
    }
}
