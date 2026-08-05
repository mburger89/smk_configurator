import SwiftCrossUI

/// The 26px status bar: connection state, active design/layer counts, and
/// firmware version on the left; unsaved-changes indicator on the right
/// (only shown when dirty).
struct StatusBarView: View {
    @Environment(EditorState.self) var editor
    @Environment(\.colorScheme) private var colorScheme
    private var chrome: Chrome { Chrome(scheme: colorScheme) }

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                StatusDot(color: editor.usbConnected ? chrome.connectedDot : chrome.disconnectedDot, diameter: 7)
                Text(editor.usbConnected ? "USB Connected" : "USB Disconnected")
            }
            Text("\(editor.activeDesign.name) · \(editor.activeDesign.rowCount)×\(editor.activeDesign.colCount)")
            Text("\(editor.document.layers.count) layers")
            Text("fw \(firmwareVersionLabel)")
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
}
