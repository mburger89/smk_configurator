import Foundation
import MetalUI
import MetalUIPortableText
import MetalUISystemFonts
import Testing
@testable import SMKConfigurator

/// Builds, lays out and draws the real shell -- `rootView(editor:)` in a
/// MetalUI window -- in every rail mode, both macro sub-states and both colour
/// schemes, through MetalUI's public API only. A MetalUI layout refusal (an
/// unlowerable field, an unconsumed item record, an overlay over several nodes)
/// traps the process in a window, so this suite passing is the claim "every
/// pane builds and lays out without trapping". It cannot see whether anything
/// looks right.
///
/// `everyModeDraws` opens a real (never displayed by the test) AppKit window,
/// so the window's own path runs: the app's `lightTheme`/`darkTheme`, the
/// window-stamped colour scheme and the lifecycle drain. `everyModeRendersHeadlessly`
/// builds the same tree with no window through the public `renderFrame`,
/// over `PortableTextSystem` + `SystemFonts` (gap MG-12 says what that path
/// does not cover).
@MainActor
@Suite("The shell builds and lays out in every mode", .serialized)
struct ShellRenderTests {
    @Test("every rail mode, both macro sub-states, light and dark")
    func everyModeDraws() throws {
        let defaults = UserDefaults(suiteName: "ShellRenderTests-\(UUID().uuidString)")!
        let editor = EditorState(userDefaults: defaults)
        let app = try App()
        ChromeTheme.apply(to: app)
        let window = try app.openWindow(
            title: "ShellRenderTests",
            size: WindowMetrics.idealSize,
            minSize: WindowMetrics.minSize,
            startsDisplayLink: false
        ) {
            rootView(editor: editor)
        }

        for scheme in [ColorScheme.light, ColorScheme.dark] {
            window.preferredColorScheme = scheme
            for mode in RailMode.allCases {
                editor.railMode = mode
                window.setNeedsRedraw()
                window.drawFrameIfNeeded()
            }
            editor.railMode = .macros
            editor.createMacro()
            editor.appendStep(MacroStepType.keystroke.makeStep())
            editor.appendStep(MacroStepType.delay.makeStep())
            #expect(editor.macroWorkspace != .library)
            window.setNeedsRedraw()
            window.drawFrameIfNeeded()
            editor.closeMacro()
            window.setNeedsRedraw()
            window.drawFrameIfNeeded()
        }
        #expect(editor.railMode == .macros)
    }

    @Test("every rail mode builds a non-empty scene with no window")
    func everyModeRendersHeadlessly() throws {
        let defaults = UserDefaults(suiteName: "ShellRenderTests-\(UUID().uuidString)")!
        let editor = EditorState(userDefaults: defaults)
        let textSystem = PortableTextSystem(resolver: try SystemFonts.resolver())
        let atlas = GlyphAtlas(width: 2048, height: 2048)
        // Light only: `renderFrame`'s `theme:` sets tokens, never the colour
        // scheme, and an `.environment(\.colorScheme, …)` root is not an
        // `Element` it accepts (gap MG-12).
        for mode in RailMode.allCases {
            editor.railMode = mode
            let scene = renderFrame({ rootView(editor: editor) },
                                    size: WindowMetrics.idealSize, scaleFactor: 2,
                                    textSystem: textSystem, atlas: atlas)
            #expect(!scene.rects.isEmpty, "\(mode): no rects")
            #expect(!scene.glyphs.isEmpty, "\(mode): no glyphs")
        }
    }

    @Test("the window's height bounds come from the palette's")
    func windowMetrics() {
        #expect(WindowMetrics.minWindowHeight == 27 + 40 + 32 + 240 + PaletteLayout.minHeight)
        #expect(WindowMetrics.idealWindowHeight > WindowMetrics.minWindowHeight)
        // Under the ~730pt of usable height a 1366x768 laptop has.
        #expect(WindowMetrics.minWindowHeight < 730)
    }

    @Test("every chrome colour differs between the light and dark schemes")
    func paletteFollowsTheScheme() {
        let colours = [Chrome.bar, Chrome.canvas, Chrome.column, Chrome.divider, Chrome.dividerLight,
                       Chrome.surface, Chrome.accent, Chrome.accentWash, Chrome.textPrimary,
                       Chrome.textSecondary, Chrome.textTertiary, Chrome.pillBackground,
                       Chrome.chipBackground, Chrome.chipBorder, Chrome.glassFill, Chrome.glassActiveFill,
                       Chrome.dangerText, Chrome.connectedDot, Chrome.disconnectedDot]
        #expect(colours.count == 19)
        var environment = EnvironmentValues()
        for colour in colours {
            environment.colorScheme = .light
            let light = colour.resolve(in: environment)
            environment.colorScheme = .dark
            let dark = colour.resolve(in: environment)
            #expect(light != dark)
        }
    }
}
