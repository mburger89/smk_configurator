import SwiftCrossUI

/// One physical key. Tapping it always focuses the Key inspector on this
/// position (`EditorState.selectKey`); if something's armed from the
/// palette drawer (`editor.selectedToken`) the tap also places it here first
/// -- the click-to-select/click-to-place substitute for drag-and-drop
/// described in the plan (SwiftCrossUI has no drag gesture as of v0.8.0).
///
/// `theme`/`interactive` let this same view render the read-only, live
/// preview board in THM mode (`theme` overrides `editor.activeTheme`,
/// `interactive: false` disables tap handling) as well as the editable KEY
/// board, so both modes render pixel-identically.
struct KeyCapView: View {
    @Environment(EditorState.self) var editor
    @Environment(\.colorScheme) private var colorScheme
    private var chrome: Chrome { Chrome(scheme: colorScheme) }

    var row: Int
    var col: Int
    var widthUnits: Double
    var theme: KeyboardTheme? = nil
    var interactive: Bool = true
    /// Resolves `macro:<id>` to the macro's name. Every other token's
    /// `displayLabel` is self-sufficient ("A", "Ctrl", "MO1"...); `.macro(n)`
    /// is the one that needs the document, so this stays optional and nil by
    /// default -- existing call sites are untouched and fall back to the
    /// token's own "M<id>" label.
    var macroName: ((Int) -> String?)? = nil

    static let unit: Double = 46
    /// Column gap -- also used directly as `KeyboardBoardView`'s row
    /// `HStack(spacing:)` so the two can't drift apart. Needed here to
    /// compute a multi-unit key's width so it spans its columns exactly
    /// (e.g. a 2.0-unit key spans two unit-width columns plus the one gap
    /// between them).
    static let spacing: Int = 10

    var body: some View {
        let token = editor.action(row: row, col: col)
        let width = widthUnits * Self.unit + (widthUnits - 1) * Double(Self.spacing)
        let activeTheme = theme ?? editor.activeTheme
        let isArmed = interactive && editor.selectedToken == token && token != .none
        let isInspected = interactive && editor.selectedKeyPosition == KeyPosition(row: row, col: col)
        let label: String = {
            if case .macro(let n) = token, let resolved = macroName?(n) {
                return resolved
            }
            return token.displayLabel
        }()

        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(activeTheme.background(for: token))
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(activeTheme.keyText.color)
        }
        .frame(width: width, height: Self.unit)
        .overlay {
            if isArmed || isInspected {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(chrome.accent, style: StrokeStyle(width: 2))
            }
        }
        .onTapGesture {
            guard interactive else { return }
            if let selected = editor.selectedToken {
                editor.assign(selected, row: row, col: col)
                editor.selectedToken = nil
            }
            editor.selectKey(row: row, col: col)
        }
    }
}
