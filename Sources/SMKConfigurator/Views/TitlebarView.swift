import SwiftCrossUI

/// The 44px titlebar: traffic lights are native/unchanged (owned by the
/// window itself, not rendered here); this view is the toolbar pill group
/// plus the right-aligned Advanced Mode switch.
struct TitlebarView: View {
    @Environment(EditorState.self) var editor
    @Environment(\.chooseFile) var chooseFile
    @Environment(\.chooseFileSaveDestination) var chooseFileSaveDestination

    var body: some View {
        HStack(spacing: 4) {
            ToolbarPill(label: "New") {
                editor.newDocument()
            }
            ToolbarPill(label: "Open") {
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
            ToolbarPill(label: "Save") {
                Task {
                    if let url = editor.fileURL {
                        editor.save(to: url)
                    } else {
                        await saveAs()
                    }
                }
            }
            ToolbarPill(label: "Save As") {
                Task { await saveAs() }
            }
            ToolbarPill(label: "Import") {
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
            ToolbarPill(label: "Export") {
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
                .foregroundColor(Chrome.textTertiary)
            Toggle("", isOn: advancedBinding)
                .toggleStyle(.switch)
                .fixedSize()
        }
        .padding(EdgeInsets(top: 0, bottom: 0, leading: 12, trailing: 12))
        .frame(height: 44)
        .background(Chrome.bar)
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
