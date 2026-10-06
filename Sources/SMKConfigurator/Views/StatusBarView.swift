import MetalUI

/// The 26px status bar: connection state, active design/layer counts, and
/// firmware version on the left; unsaved-changes indicator on the right
/// (only shown when dirty).
struct StatusBarView: Component {
    let editor: EditorState

    /// Status-bar half of contract C2 ("warns in the library row and status
    /// bar"; see `docs/superpowers/specs/2026-08-20-macro-creation-design.md`).
    /// `nil` whenever there's nothing to say, or whenever `editor.railMode`
    /// is already `.macros` -- both the library banner and the step editor's
    /// SLOT line already show `MacroBudget.blockReason` in full there, so
    /// repeating it here would be a second identical warning inches away.
    /// Everywhere else -- notably KEY mode, where a user has no other window
    /// onto macro capacity -- this is the only sign a macro won't flash.
    private var macroWarningReason: String? {
        guard editor.railMode != .macros else { return nil }
        return editor.macroBudget.blockReason
    }

    var content: some ElementGroup {
        Row(gap: Pixels(16)) {
            Row(gap: Pixels(6)) {
                StatusDot(color: editor.usbConnected ? Chrome.connectedDot : Chrome.disconnectedDot, diameter: 7)
                Text(editor.usbConnected ? "USB Connected" : "USB Disconnected")
            }
            Text("\(editor.activeDesign.name) · \(editor.activeDesign.rowCount)×\(editor.activeDesign.colCount)")
            Text("\(editor.document.layers.count) layers")
            Text("fw \(firmwareVersionLabel)")
            if let macroWarningReason {
                macroWarning(macroWarningReason)
            }
            Spacer()
            if editor.isDirty {
                Text("\(keymapFileName) — unsaved changes")
            }
        }
        .padding(Insets.symmetric(horizontal: 16))
        .frame(maxWidth: Pixels(.infinity), minHeight: Pixels(26), maxHeight: Pixels(26))
        .background(Chrome.bar)
        .font(.system(size: 11))
        .foregroundColor(Chrome.textTertiary)
        .onAppear { [editor] in
            editor.refreshDeviceStatus()
        }
    }

    private var keymapFileName: String {
        editor.fileURL?.lastPathComponent ?? "keymap.json"
    }

    /// Compressed form of `blockReason` -- this bar is 26pt of chrome that's
    /// always on screen, with no room for the full sentence. The full text is
    /// a hover away via `.help(_:)`.
    ///
    /// A *measured* overflow (a real board answered, `!isEstimate`) gets the
    /// same visual weight as an actual blocking condition: bold, `dangerText`.
    /// An *estimated* one stays at the bar's ordinary weight and colour.
    private func macroWarning(_ reason: String) -> Text {
        let budget = editor.macroBudget
        return Text(budget.isEstimate ? "Macros may not fit (estimated)" : "Macros won't fit")
            .fontWeight(budget.isEstimate ? .regular : .semibold)
            .foregroundColor(budget.isEstimate ? Chrome.textTertiary : Chrome.dangerText)
            .help(reason)
    }
}
