import MetalUI

/// One physical key. Clicking it focuses the Key inspector on this position
/// (`EditorState.selectKey`); dropping a palette chip on it assigns the chip's
/// action to it on the current layer (and inspects it). While a chip is
/// dragged over it, and while it is the inspected key, it wears a 2-point
/// accent ring.
///
/// The previous build had no drag and drop (SwiftCrossUI 0.8 has no drag
/// gesture), so it armed a chip with one click and placed it with a second on
/// a key (`editor.selectedToken`, the armed ring, the inspector's Reassign).
/// That substitute is gone (port plan §2.2 W5): a chip is dragged here, or
/// clicked to assign it to the inspected key (`PaletteChip`).
///
/// `theme`/`interactive` let the same view draw the THM mode's read-only live
/// preview (`theme` overrides `editor.activeTheme`; `interactive: false`
/// drops the click, the drop and the ring) as well as the editable KEY board,
/// so both draw identically.
struct KeyCapView: Component {
    let editor: EditorState
    var row: Int
    var col: Int
    var widthUnits: Double
    var theme: KeyboardTheme? = nil
    var interactive: Bool = true

    /// Whether a dragged chip is over this key, written by the drop
    /// destination's `isTargeted` callback (input, never a phase).
    @State var isTargeted = false

    /// One key unit's side, and the column gap -- also `KeyboardBoardView`'s
    /// row spacing, so a multi-unit key spans its columns exactly (a 2U key is
    /// two unit-width columns plus the gap between them).
    static let unit: Float = 46
    static let spacing: Float = 10

    static func width(units: Double) -> Float {
        Float(units) * unit + (Float(units) - 1) * spacing
    }

    var content: some ElementGroup {
        if interactive {
            Button(action: inspect) {
                face
            }
            .buttonStyle(.plain)
            .background(fill)
            .cornerRadius(Pixels(6))
            .border(isRinged ? Chrome.accent : Color.clear, width: Pixels(2))
            .dropDestination(for: String.self, action: drop, isTargeted: { [$isTargeted] in
                $isTargeted.wrappedValue = $0
            })
        } else {
            face
                .background(fill)
                .cornerRadius(Pixels(6))
        }
    }

    private var token: ActionToken {
        editor.action(row: row, col: col)
    }

    private var activeTheme: KeyboardTheme {
        theme ?? editor.activeTheme
    }

    private var fill: Color {
        activeTheme.background(for: token).color
    }

    private var isRinged: Bool {
        isTargeted || editor.selectedKeyPosition == KeyPosition(row: row, col: col)
    }

    /// A macro token shows its macro's name; every other token's
    /// `displayLabel` is self-sufficient ("A", "Ctrl", "MO1", …).
    private var label: String {
        if case .macro(let id) = token, let name = editor.macroName(for: id) {
            return name
        }
        return token.displayLabel
    }

    private var face: ModifiedElement<Text> {
        Text(label)
            .font(.system(size: 12))
            .foregroundColor(activeTheme.keyText.color)
            .frame(width: Pixels(Self.width(units: widthUnits)), height: Pixels(Self.unit))
    }

    private func inspect() {
        editor.selectKey(row: row, col: col)
    }

    private func drop(_ items: [String], _ location: Point<Pixels>) -> Bool {
        guard let token = PaletteDrop.token(from: items) else { return false }
        editor.assign(token, row: row, col: col)
        editor.selectKey(row: row, col: col)
        return true
    }
}

/// What a palette chip carries while dragged, and how a key reads it back.
/// A chip drags its token's `canonicalString` (a plain `String`, so the drag
/// needs no custom content type); a key accepts the first dropped string that
/// parses to a known action. Text dragged in from another app parses to
/// `.raw` and is refused, so it cannot overwrite a key with junk.
enum PaletteDrop {
    static func payload(for token: ActionToken) -> String {
        token.canonicalString
    }

    static func token(from items: [String]) -> ActionToken? {
        for item in items {
            let token = ActionToken.parse(item)
            if case .raw = token { continue }
            return token
        }
        return nil
    }
}
