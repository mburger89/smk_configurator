import DefaultBackend
import SwiftCrossUI

@main
struct SMKConfiguratorApp: App {
    @State var editor = EditorState()

    var body: some Scene {
        WindowGroup("SMK Keymap Configurator") {
            ContentView()
                .environment(editor)
                .preferredColorScheme(editor.appearanceMode.colorScheme)
        }
        // Opens tall enough for the whole palette; the OS clamps this down
        // to the display and `ContentView.minWindowHeight` (well under a
        // 1366x768 screen) is what the window can be dragged down to.
        .defaultSize(width: 1440, height: Int(ContentView.idealWindowHeight.rounded(.up)))
        .commands {
            CommandMenu("View") {
                Menu("Appearance") {
                    ForEach(AppearanceMode.allCases) { mode in
                        Toggle(
                            mode.rawValue.capitalized,
                            isOn: Binding(
                                get: { editor.appearanceMode == mode },
                                set: { isOn in if isOn { editor.setAppearanceMode(mode) } }
                            )
                        )
                    }
                }
            }
        }
    }
}
