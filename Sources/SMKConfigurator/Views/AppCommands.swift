import Foundation
import MetalUI

/// The menu bar (`App.commands`): the File menu's keymap actions -- read from
/// `FileCommand.all`, the table the Linux/Windows toolbar reads too
/// (`PlatformToolbar.swift`) -- and the View menu's Advanced Mode and
/// Appearance. On macOS every MetalUI app also gets the standard AppKit menu
/// (About, Hide, Quit, Close, Edit, Window). On SDL the bar is recorded and
/// drawn nowhere (gap MG-23): its shortcuts still fire through the window's
/// command stage, and the toolbar strip carries every item.
///
/// The commands are re-evaluated whenever the bar is needed, so the checked
/// items read the model fresh.
@MainActor
func installAppCommands(app: App, window: Window, editor: EditorState) {
    let dialogs = window.fileDialogs
    app.commands {
        CommandGroup(replacing: .newItem) {
            for command in FileCommand.all {
                if command.startsGroup {
                    Divider()
                }
                Button(command.title) { command.action(editor, dialogs) }
                    .keyboardShortcut(command.shortcut)
            }
        }
        CommandMenu("View") {
            Toggle("Advanced Mode", isOn: Binding(get: { editor.showAdvanced },
                                                  set: { editor.setShowAdvanced($0) }))
            Menu("Appearance") {
                for mode in AppearanceMode.allCases {
                    Toggle(mode.rawValue.capitalized,
                           isOn: Binding(get: { editor.appearanceMode == mode },
                                         set: { isOn in if isOn { editor.setAppearanceMode(mode) } }))
                }
            }
        }
    }
}

/// The keymap's file actions, through MetalUI's file dialogs. Each runs in a
/// main-actor task (the dialogs are `async`); `main.swift` calls `app.run()`
/// from top-level code, so those tasks' continuations run. A cancelled dialog
/// does nothing; a dialog that fails to open reports through
/// `editor.loadError`, which the window shows as an alert. MetalUI's dialogs
/// take no title and no starting directory (gap MG-5), so "Open keymap.json"
/// and the `~/esp/SMK` start are gone; the panel opens where AppKit last left
/// it.
@MainActor
enum KeymapFileActions {
    static func open(editor: EditorState, dialogs: FileDialogs) {
        Task { @MainActor in
            guard let url = await chooseFile(editor: editor, dialogs: dialogs) else { return }
            editor.load(from: url)
        }
    }

    static func importKeymap(editor: EditorState, dialogs: FileDialogs) {
        open(editor: editor, dialogs: dialogs)
    }

    static func save(editor: EditorState, dialogs: FileDialogs) {
        if let url = editor.fileURL {
            editor.save(to: url)
        } else {
            saveAs(editor: editor, dialogs: dialogs)
        }
    }

    static func saveAs(editor: EditorState, dialogs: FileDialogs) {
        Task { @MainActor in
            guard let url = await chooseDestination(editor: editor, dialogs: dialogs,
                                                    defaultFilename: "keymap.json") else { return }
            editor.save(to: url)
        }
    }

    static func exportKeymap(editor: EditorState, dialogs: FileDialogs) {
        Task { @MainActor in
            guard let url = await chooseDestination(editor: editor, dialogs: dialogs,
                                                    defaultFilename: "keymap.json") else { return }
            editor.exportKeymap(to: url)
        }
    }

    /// One JSON file, or `nil` on cancel or failure (reported).
    static func chooseFile(editor: EditorState, dialogs: FileDialogs) async -> URL? {
        do {
            return try await dialogs.openFiles(allowedContentTypes: [.json]).first
        } catch {
            editor.loadError = "Couldn't show the open panel: \(error)"
            return nil
        }
    }

    /// A save destination, or `nil` on cancel or failure (reported).
    static func chooseDestination(editor: EditorState, dialogs: FileDialogs, defaultFilename: String) async -> URL? {
        do {
            return try await dialogs.saveFile(contentTypes: [.json], defaultFilename: defaultFilename)
        } catch {
            editor.loadError = "Couldn't show the save panel: \(error)"
            return nil
        }
    }
}
