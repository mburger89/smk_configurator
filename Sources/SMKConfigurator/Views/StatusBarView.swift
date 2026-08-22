import SwiftCrossUI

/// The 26px status bar: connection state, active design/layer counts, and
/// firmware version on the left; unsaved-changes indicator on the right
/// (only shown when dirty).
struct StatusBarView: View {
    @Environment(EditorState.self) var editor
    @Environment(\.colorScheme) private var colorScheme
    private var chrome: Chrome { Chrome(scheme: colorScheme) }

    /// Status-bar half of contract C2 ("warns in the library row and status
    /// bar"; see `docs/superpowers/specs/2026-08-20-macro-creation-design.md`).
    /// `nil` whenever there's nothing to say, or whenever `editor.railMode`
    /// is already `.macros` -- both the library banner (`MacroLibraryView.
    /// capacityBanner`) and the step editor's SLOT line (`MacroEditorViews`)
    /// already show `MacroBudget.blockReason` in full there, so repeating it
    /// here would be a second identical warning inches away. Everywhere
    /// else -- notably KEY mode, where a user has no other window onto
    /// macro capacity -- this is the only sign a macro won't flash.
    private var macroBudget: MacroBudget { editor.macroBudget }

    private var macroWarningReason: String? {
        guard editor.railMode != .macros else { return nil }
        return macroBudget.blockReason
    }

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                StatusDot(color: editor.usbConnected ? chrome.connectedDot : chrome.disconnectedDot, diameter: 7)
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
        .font(.system(size: 11))
        .foregroundColor(chrome.textTertiary)
        .padding(EdgeInsets(top: 0, bottom: 0, leading: 16, trailing: 16))
        .frame(height: 26)
        .background(chrome.bar)
        .onAppear {
            editor.refreshDeviceStatus()
        }
    }

    private var keymapFileName: String {
        editor.fileURL?.lastPathComponent ?? "keymap.json"
    }

    /// Compressed form of `blockReason` -- this bar is 26pt of chrome that's
    /// always on screen, with no room for the full sentence
    /// ("Macros exceed this board's memory by 42 bytes.", etc). The full
    /// text is a hover away via `.help(_:)`, the same mechanism the icon-only
    /// titlebar buttons (`UIStyle.swift`'s `ToolbarIconButton`) use to carry
    /// a full name behind a compact glyph; it also lives permanently in the
    /// MACROS rail mode views this warning is suppressed against.
    ///
    /// A *measured* overflow (a real board answered, `!isEstimate`) gets
    /// the same visual weight as an actual blocking condition: bold,
    /// `dangerText`. An *estimated* one (no board has ever answered --
    /// `MacroCapacity.floor` -- or a remembered `.lastKnown` reading) is
    /// real but softer: the meter itself says "(estimated)" for a reason,
    /// so this stays at the bar's ordinary weight/color rather than
    /// shouting as loud as a number a board actually confirmed.
    private func macroWarning(_ reason: String) -> some View {
        Text(macroBudget.isEstimate ? "Macros may not fit (estimated)" : "Macros won't fit")
            .fontWeight(macroBudget.isEstimate ? .regular : .semibold)
            .foregroundColor(macroBudget.isEstimate ? chrome.textTertiary : chrome.dangerText)
            .help(reason)
    }
}
