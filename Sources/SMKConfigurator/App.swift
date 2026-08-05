import DefaultBackend
import SwiftCrossUI

@main
struct SMKConfiguratorApp: App {
    @State var editor = EditorState()

    var body: some Scene {
        WindowGroup("SMK Keymap Configurator") {
            ContentView()
                .environment(editor)
        }
        .defaultSize(width: 1440, height: 900)
    }
}
