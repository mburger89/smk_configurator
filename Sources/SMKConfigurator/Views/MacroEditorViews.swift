import MetalUI

// The MACROS step editor's palette column and canvas header (port plan §1.10).
// (`MacroStepType` lives in `Model/MacroUITypes.swift`; its badge colour in
// `ThemeColor+MetalUI.swift`.)

/// The step editor's left column: ADD STEP (click a type to insert it after
/// the selection, or drag it onto the canvas's "Add a step" card to append
/// it), CAPTURE (honestly disabled), the SLOT meter, and Back to library.
struct MacroStepPaletteView: Component {
    let editor: EditorState

    /// The column's width, and the SLOT track's (the width less its padding):
    /// a known constant rather than a measurement.
    static let width: Float = 212
    static let outerPadding: Float = 12
    static let trackWidth: Float = width - 2 * outerPadding

    var content: some ElementGroup {
        pane {
            Column(gap: Pixels(18)) {
                addStepSection
                captureSection
                slotSection
                Spacer()
                InspectorButton(label: "Back to library") { [editor] in editor.closeMacro() }
            }
            .alignItems(.stretch)
            .padding(Insets.symmetric(horizontal: Self.outerPadding, vertical: 14))
            .frame(minWidth: Pixels(Self.width), maxWidth: Pixels(Self.width), maxHeight: Pixels(.infinity),
                   alignment: .top)
            .background(Chrome.column)
        }
    }

    private var addStepSection: some Element {
        let editor = editor
        // The top-level palette never sits inside a repeat block: the step
        // list has no nested selection (a repeat block's contents are edited
        // in the inspector), so RPT is always offered here.
        return Column(gap: Pixels(6)) {
            SectionHeader(title: "Add step")
            for type in MacroStepType.available(insideRepeatBlock: false) {
                MacroStepTypeRow(type: type, theme: editor.activeTheme, isDraggable: true) {
                    editor.insertStepAfterSelection(type.makeStep())
                }
            }
        }
        .alignItems(.stretch)
    }

    /// Recording from the board needs a device-to-host event channel neither
    /// transport has, so this is a real disabled button (`.disabled`, the one
    /// gate, and `Button`'s own disabled look -- the previous build faded a
    /// fake button's colours by hand, §2.2 W3).
    private var captureSection: some Element {
        Column(gap: Pixels(6)) {
            SectionHeader(title: "Capture")
            Button {} label: {
                Text("Record from board")
                    .font(.system(size: 12))
                    .foregroundColor(Chrome.textPrimary)
                    .frame(maxWidth: Pixels(.infinity), minHeight: Pixels(30), maxHeight: Pixels(30))
            }
            .buttonStyle(.plain)
            .background(Chrome.pillBackground)
            .cornerRadius(Pixels(6))
            .help("Recording macros from the board isn't implemented yet.")
            .disabled(true)
            Text("Recording from the board isn't available yet.")
                .font(.system(size: 11))
                .foregroundColor(Chrome.textTertiary)
        }
        .alignItems(.stretch)
    }

    private var slotSection: some Element {
        let budget = editor.macroBudget
        // `MacroDefinition.id` is the firmware slot number, the same one the
        // canvas header's "macro:<id>" shows.
        let slot = editor.currentMacro?.id ?? 0
        let fill = Self.trackWidth * Float(min(max(budget.fillFraction, 0), 1))
        return Column(gap: Pixels(6)) {
            SectionHeader(title: "Slot")
            Row(gap: Pixels(0)) {
                Box()
                    .frame(width: Pixels(fill), height: Pixels(5))
                    .background(budget.canFlash ? Chrome.accent : Chrome.dangerText)
                    .cornerRadius(Pixels(2.5))
                Spacer()
            }
            .frame(width: Pixels(Self.trackWidth), height: Pixels(5))
            .background(Chrome.dividerLight)
            .cornerRadius(Pixels(2.5))
            Text(budget.summaryLabel(slot: slot))
                .font(.system(size: 11))
                .foregroundColor(Chrome.textTertiary)
            if let blockReason = budget.blockReason {
                Text(blockReason)
                    .font(.system(size: 11))
                    .foregroundColor(Chrome.dangerText)
            }
        }
        .alignItems(.flexStart)
    }
}

/// One ADD STEP row: a 28-point badge in the active theme's role colour and
/// the type's label, 36 high. A real `Button` -- a click runs `insert` -- and,
/// where `isDraggable`, a drag source carrying `type.rawValue`, which the
/// canvas's "Add a step" card accepts (port plan §2.2 W6; the previous build
/// had no drag gesture and offered the card as a click-only substitute).
///
/// Shared with the inspector's repeat-block editor, whose nested ADD STEP list
/// is not draggable (a drop on the canvas appends at the top level).
struct MacroStepTypeRow: Component {
    var type: MacroStepType
    var theme: KeyboardTheme
    var isDraggable: Bool = false
    var insert: @MainActor () -> Void

    var content: some ElementGroup {
        if isDraggable {
            button.draggable(MacroStepDrop.payload(for: type))
        } else {
            button
        }
    }

    private var button: some StyledElement {
        Button(action: insert) {
            Row(gap: Pixels(8)) {
                badge
                Text(type.label)
                    .font(.system(size: 12))
                    .foregroundColor(Chrome.textPrimary)
                Spacer()
            }
            .alignItems(.center)
            .padding(Insets.symmetric(horizontal: 8))
            .frame(maxWidth: Pixels(.infinity), minHeight: Pixels(36), maxHeight: Pixels(36))
        }
        .buttonStyle(.plain)
        .background(Chrome.chipBackground)
        .cornerRadius(Pixels(6))
    }

    /// Theme role colours are user data (literal `Color`s); Repeat block has
    /// no role and takes the neutral pill background.
    private var badge: some Element {
        let themeColor = type.badgeColor(theme: theme)
        return Text(type.badge)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(themeColor != nil ? theme.keyText.color : Chrome.textPrimary)
            .frame(width: Pixels(28), height: Pixels(28))
            .background(themeColor ?? Chrome.pillBackground)
            .cornerRadius(Pixels(4))
    }
}

/// What an ADD STEP row carries while dragged, and how the "Add a step" card
/// reads it back: the type's raw value, a plain `String`. Anything else (text
/// dragged in from another app) is refused.
enum MacroStepDrop {
    static func payload(for type: MacroStepType) -> String {
        type.rawValue
    }

    static func type(from items: [String]) -> MacroStepType? {
        items.lazy.compactMap(MacroStepType.init(rawValue:)).first
    }
}

/// The step editor's canvas header: the open macro's name and its metadata
/// line, then Test run and Save. Empty when no macro is open (which the
/// shell never shows, but is safer than force-unwrapping).
///
/// Save returns to the library: macro edits are committed live through
/// `editor.updateMacro(_:)`, so there is nothing to flush. Test run is real:
/// it switches the inspector to Timing, where the per-step timing trace and
/// its "doesn't send keystrokes" disclaimer live.
struct MacroCanvasHeaderView: Component {
    let editor: EditorState

    var content: some ElementGroup {
        if let macro = editor.currentMacro {
            let editor = editor
            Row(gap: Pixels(12)) {
                Column(gap: Pixels(2)) {
                    Text(macro.name)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(Chrome.textPrimary)
                    Text(macro.canvasSummary)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Chrome.textSecondary)
                }
                .alignItems(.flexStart)
                Spacer()
                PillButton(label: "Test run",
                           help: "Walks the macro's steps and shows the timing trace in the inspector. Doesn't send keystrokes.") {
                    editor.macroInspectorTab = .timing
                }
                PillButton(label: "Save", isAccent: true) { editor.closeMacro() }
            }
            .alignItems(.center)
            .padding(Insets.edges(top: 16, leading: 16, bottom: 12, trailing: 16))
            .frame(maxWidth: Pixels(.infinity))
        }
    }
}
