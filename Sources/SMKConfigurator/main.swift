import MetalUI

// The SMK keymap configurator: one MetalUI window over one `EditorState`.
//
// **Top-level code, not `@main`**: `app.run()` must be called synchronously
// from here. Under an async main, MetalUI's run loop executes inside a
// main-actor job and the main queue never drains -- a `Task { @MainActor in
// … }` from a button, the continuation of an awaited file dialog, and the
// device monitor's polling loop would never run (MetalUI ruling SV-H;
// docs/getting-started.md, "Call app.run() from top-level code").

let editor = EditorState()

let app = try App()
ChromeTheme.apply(to: app)

let window = try app.openWindow(
    title: "SMK Keymap Configurator",
    size: WindowMetrics.idealSize,
    minSize: WindowMetrics.minSize
) {
    rootView(editor: editor)
}

installAppCommands(app: app, window: window, editor: editor)

app.run()
