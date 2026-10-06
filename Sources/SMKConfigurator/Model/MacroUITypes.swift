import Foundation

// View-logic types of the MACROS step editor, moved verbatim out of `Views/`
// (port plan §4.3 item 3) so the model -- which stores a `MacroInspectorTab`
// and builds steps from a `MacroStepType` -- compiles without the UI on Linux
// and Windows.

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

    // `badgeColor(theme:)` (the badge's fill) lives with the views, in
    // `Views/ThemeColor+MetalUI.swift`, so the model names no UI type.

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
