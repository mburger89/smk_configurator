import SwiftCrossUI

/// The 44px titlebar: traffic lights are native/unchanged (owned by the
/// window itself, not rendered here); this view is the toolbar pill group
/// plus the right-aligned Advanced Mode switch.
struct TitlebarView: View {
    @Environment(EditorState.self) var editor
    @Environment(\.chooseFile) var chooseFile
    @Environment(\.chooseFileSaveDestination) var chooseFileSaveDestination
    @Environment(\.colorScheme) private var colorScheme
    private var chrome: Chrome { Chrome(scheme: colorScheme) }

    var body: some View {
        HStack(spacing: 8) {
            ToolbarIconButton(icon: .newDoc, tooltip: "New") {
                editor.newDocument()
            }
            ToolbarIconButton(icon: .open, tooltip: "Open") {
                Task {
                    guard
                        let url = await chooseFile(
                            title: "Open keymap.json",
                            initialDirectory: defaultKeymapURL.deletingLastPathComponent()
                        )
                    else { return }
                    editor.load(from: url)
                }
            }
            ToolbarIconButton(icon: .save, tooltip: "Save") {
                Task {
                    if let url = editor.fileURL {
                        editor.save(to: url)
                    } else {
                        await saveAs()
                    }
                }
            }
            ToolbarIconButton(icon: .saveAs, tooltip: "Save As") {
                Task { await saveAs() }
            }
            ToolbarIconButton(icon: .importFile, tooltip: "Import") {
                Task {
                    guard
                        let url = await chooseFile(
                            title: "Import keymap.json",
                            initialDirectory: defaultKeymapURL.deletingLastPathComponent()
                        )
                    else { return }
                    editor.load(from: url)
                }
            }
            ToolbarIconButton(icon: .exportFile, tooltip: "Export") {
                Task {
                    guard
                        let url = await chooseFileSaveDestination(
                            title: "Export keymap",
                            defaultFileName: "keymap.json"
                        )
                    else { return }
                    editor.exportKeymap(to: url)
                }
            }
            Spacer()
            Text("Advanced Mode")
                .font(.system(size: 12))
                .foregroundColor(chrome.textTertiary)
            Toggle("", isOn: advancedBinding)
                .toggleStyle(.switch)
                .fixedSize()
        }
        .padding(8)
        .frame(height: 40)
        .background(chrome.bar)
    }

    private var advancedBinding: Binding<Bool> {
        Binding(get: { editor.showAdvanced }, set: { editor.setShowAdvanced($0) })
    }

    private func saveAs() async {
        guard
            let url = await chooseFileSaveDestination(
                title: "Save keymap.json",
                initialDirectory: defaultKeymapURL.deletingLastPathComponent(),
                defaultFileName: "keymap.json"
            )
        else { return }
        editor.save(to: url)
    }
}
