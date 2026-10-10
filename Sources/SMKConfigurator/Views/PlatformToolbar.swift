import Foundation
import MetalUI

/// The modifier every app shortcut uses: ⌘ on macOS, Ctrl on Linux and
/// Windows. MetalUI's `.keyboardShortcut` defaults to `.command`, which SDL
/// maps to the Super/Windows key, and Windows reserves Win+N, Win+O and Win+S
/// itself (gap MG-24). MetalUI's text fields already make the same switch for
/// their editing keys.
#if os(macOS)
let primaryShortcutModifier: EventModifiers = .command
#else
let primaryShortcutModifier: EventModifiers = .control
#endif

/// One file action of the keymap: the File menu's item and, on Linux and
/// Windows, the toolbar's icon button. `FileCommand.all` is the one table
/// both read (cross-platform plan §1.2 M1), so the two cannot drift.
struct FileCommand {
    /// The menu item's title (macOS's, unchanged by the cross-platform port).
    let title: String
    /// The toolbar button's icon, pre-rendered per platform (`IconLoader`).
    let icon: AppIcon
    /// `nil` for Import… and Export…, which have none.
    let shortcut: KeyboardShortcut?
    /// Whether the menu draws a divider before this item.
    let startsGroup: Bool
    let action: @MainActor (_ editor: EditorState, _ dialogs: FileDialogs) -> Void

    /// The File menu's order: New, Open… | Save, Save As… | Import…, Export….
    @MainActor static let all: [FileCommand] = [
        FileCommand(title: "New", icon: .newDoc,
                    shortcut: KeyboardShortcut("n", modifiers: primaryShortcutModifier),
                    startsGroup: false, action: { editor, _ in editor.newDocument() }),
        FileCommand(title: "Open…", icon: .open,
                    shortcut: KeyboardShortcut("o", modifiers: primaryShortcutModifier),
                    startsGroup: false,
                    action: { editor, dialogs in KeymapFileActions.open(editor: editor, dialogs: dialogs) }),
        FileCommand(title: "Save", icon: .save,
                    shortcut: KeyboardShortcut("s", modifiers: primaryShortcutModifier),
                    startsGroup: true,
                    action: { editor, dialogs in KeymapFileActions.save(editor: editor, dialogs: dialogs) }),
        FileCommand(title: "Save As…", icon: .saveAs,
                    shortcut: KeyboardShortcut("s", modifiers: [primaryShortcutModifier, .shift]),
                    startsGroup: false,
                    action: { editor, dialogs in KeymapFileActions.saveAs(editor: editor, dialogs: dialogs) }),
        FileCommand(title: "Import…", icon: .importFile, shortcut: nil, startsGroup: true,
                    action: { editor, dialogs in KeymapFileActions.importKeymap(editor: editor, dialogs: dialogs) }),
        FileCommand(title: "Export…", icon: .exportFile, shortcut: nil, startsGroup: false,
                    action: { editor, dialogs in KeymapFileActions.exportKeymap(editor: editor, dialogs: dialogs) }),
    ]

    /// The toolbar item's id (MetalUI keys each strip item by it).
    var toolbarID: String { "file.\(icon.rawValue)" }

    /// The title without its ellipsis: the toolbar button's accessibility label.
    var plainTitle: String { title.replacingOccurrences(of: "…", with: "") }

    /// The tooltip: the title and, when there is one, the shortcut
    /// ("Save As (Ctrl+Shift+S)").
    var helpText: String {
        guard let shortcut else { return plainTitle }
        var keys: [String] = []
        if shortcut.modifiers.contains(.command) { keys.append("⌘") }
        if shortcut.modifiers.contains(.control) { keys.append("Ctrl") }
        if shortcut.modifiers.contains(.option) { keys.append("Alt") }
        if shortcut.modifiers.contains(.shift) { keys.append("Shift") }
        keys.append(String(shortcut.key.character).uppercased())
        return "\(plainTitle) (\(keys.joined(separator: "+")))"
    }
}

/// The toolbar strip's icons are 48-pixel files drawn at 16 points.
private let toolbarIconScale: Float = 3

extension ElementGroup {
    /// The window's toolbar on Linux and Windows: the File menu's six actions
    /// as icon buttons, then "Advanced" and "Appearance" (the View menu). SDL
    /// draws no menu bar, so without it Import…, Export… and the View menu
    /// would be unreachable (gap MG-23); MetalUI draws the toolbar as a
    /// 39-point strip across the window's top (divergence 136, `MD-K`).
    ///
    /// **Compiled out on macOS**, where it returns `self`: the menu bar has
    /// every item, and a macOS toolbar would bring back the icons the user
    /// removed with the old titlebar (port plan §2.2 W8). A toolbar scope is
    /// not an `Element` (`MD-S`): `ContentView` writes this inside the root's
    /// `Column`.
    @MainActor
    func platformToolbar(editor: EditorState, dialogs: FileDialogs, colorScheme: ColorScheme) -> some ElementGroup {
        #if os(macOS)
        self
        #else
        fileToolbar(editor: editor, dialogs: dialogs, colorScheme: colorScheme)
        #endif
    }

    /// The toolbar itself, on every platform so a macOS test can build it
    /// (`PlatformChromeTests`); only `platformToolbar` decides where it is
    /// used.
    @MainActor
    func fileToolbar(editor: EditorState, dialogs: FileDialogs, colorScheme: ColorScheme) -> ToolbarScope<Self> {
        toolbar {
            for command in FileCommand.all {
                ToolbarItem(id: command.toolbarID, placement: .navigation) {
                    if let bitmap = IconLoader.bitmap(for: command.icon, colorScheme: colorScheme) {
                        Button(action: { command.action(editor, dialogs) }) {
                            Image(bitmap, scale: toolbarIconScale, label: Text(command.plainTitle))
                        }
                        .help(command.helpText)
                    } else {
                        Button(command.icon.fallbackLabel) { command.action(editor, dialogs) }
                            .help(command.helpText)
                    }
                }
            }
            ToolbarItem(id: "view.advanced") {
                Toggle("Advanced", isOn: Binding(get: { editor.showAdvanced },
                                                 set: { editor.setShowAdvanced($0) }))
            }
            ToolbarItem(id: "view.appearance") {
                Picker("Appearance", selection: Binding(get: { editor.appearanceMode },
                                                        set: { editor.setAppearanceMode($0) })) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.rawValue.capitalized).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }
}
