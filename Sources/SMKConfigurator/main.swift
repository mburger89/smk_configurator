import MetalUI
#if canImport(MetalUISDL)
import MetalUIPortableText
import MetalUISDL
import MetalUISystemFonts
#endif

// The SMK keymap configurator: one MetalUI window over one `EditorState`.
//
// **Top-level code, not `@main`**: `app.run()` must be called synchronously
// from here. Under an async main, MetalUI's run loop executes inside a
// main-actor job and the main queue never drains -- a `Task { @MainActor in
// … }` from a button, the continuation of an awaited file dialog, and the
// device monitor's polling loop would never run (MetalUI ruling SV-H;
// docs/getting-started.md, "Call app.run() from top-level code").

/// AppKit and Metal on macOS; SDL3 with MetalUI's portable text, over the
/// platform's installed fonts, on Linux and Windows (cross-platform plan A1;
/// the shape `metalui new --cross-platform` generates).
@MainActor
func makeApp() throws -> App {
    #if canImport(MetalUISDL)
    let resolver = try SystemFonts.resolver()
    // `SystemFonts.resolver()` registers no family for `.monospaced`, so the
    // hex fields and byte counts would draw in the sans default (gap MG-25).
    // A family that is not installed falls back to the default face.
    #if os(Windows)
    resolver.register(design: .monospaced, family: "Consolas")
    #else
    resolver.register(design: .monospaced, family: "DejaVu Sans Mono")
    #endif
    return App(platform: try SDLPlatform(), textSystem: { PortableTextSystem(resolver: resolver) })
    #else
    return try App()
    #endif
}

let editor = EditorState()

let app = try makeApp()
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
