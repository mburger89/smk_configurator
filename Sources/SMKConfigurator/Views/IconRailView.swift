import MetalUI

/// The leftmost 64px pane: 5 square buttons that switch the whole workspace
/// between KEY/DSN/THM/DEV/MAC. The only navigation in this screen -- no back
/// button, since state is mode-based rather than stack-based.
struct IconRailView: Component {
    let editor: EditorState

    var content: some ElementGroup {
        Column(gap: Pixels(16)) {
            rail(.key, icon: .key, tooltip: "Keymap")
            rail(.designs, icon: .designs, tooltip: "Designs")
            rail(.themes, icon: .themes, tooltip: "Themes")
            rail(.device, icon: .device, tooltip: "Device")
            rail(.macros, icon: .macros, tooltip: "Macros")
        }
        .padding(Insets.symmetric(vertical: 16))
        .frame(minWidth: Pixels(64), maxWidth: Pixels(64), maxHeight: Pixels(.infinity), alignment: .top)
        .background(Chrome.bar)
    }

    private func rail(_ mode: RailMode, icon: AppIcon, tooltip: String) -> RailButton {
        RailButton(icon: icon, tooltip: tooltip, isActive: editor.railMode == mode) { [editor] in
            editor.railMode = mode
        }
    }
}
