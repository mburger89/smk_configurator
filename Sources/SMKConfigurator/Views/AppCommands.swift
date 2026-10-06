import Foundation
import MetalUI

/// The menu bar (`App.commands`): the File menu's keymap actions -- once the
/// previous build's fake titlebar icons (MetalUI has no window toolbar, gap
/// MG-3) -- and the View menu's Advanced Mode and Appearance. Every MetalUI app
/// also gets the standard AppKit menu (About, Hide, Quit, Close, Edit, Window).
///
/// The commands are re-evaluated whenever the bar is needed, so the checked
/// items read the model fresh.
@MainActor
func installAppCommands(app: App, window: Window, editor: EditorState) {
    app.commands {
        CommandGroup(replacing: .newItem) {
            Button("New") { editor.newDocument() }
                .keyboardShortcut("n")
            Button("Open…") { KeymapFileActions.open(editor: editor, dialogs: window.fileDialogs) }
                .keyboardShortcut("o")
            Divider()
            Button("Save") { KeymapFileActions.save(editor: editor, dialogs: window.fileDialogs) }
                .keyboardShortcut("s")
            Button("Save As…") { KeymapFileActions.saveAs(editor: editor, dialogs: window.fileDialogs) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Divider()
            Button("Import…") { KeymapFileActions.importKeymap(editor: editor, dialogs: window.fileDialogs) }
            Button("Export…") { KeymapFileActions.exportKeymap(editor: editor, dialogs: window.fileDialogs) }
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
