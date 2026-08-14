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
        // Must be >= ContentView's minHeight (1080) -- a smaller default
        // would just get silently clamped up to the floor at launch.
        .defaultSize(width: 1440, height: 1080)
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
