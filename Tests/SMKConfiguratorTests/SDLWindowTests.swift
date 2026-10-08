// Compiled only off macOS: SDL video initialised in a macOS test process can
// `exit(0)` mid-run (MetalUI CLAUDE.md, CI hazards), and `ShellRenderTests.
// everyModeDraws` is the AppKit twin of this test.
#if !os(macOS) && canImport(MetalUISDL)
import Foundation
import MetalUI
import MetalUIPortableText
import MetalUISDL
import MetalUISystemFonts
import Testing
@testable import SMKConfigurator

/// Whether this run opens SDL windows: `SMK_RUN_SDL_WINDOW_TEST=1`. Off by
/// default, because an SDL window needs a video driver (CI's Linux image sets
/// `offscreen`; a Windows SSH session has no desktop and cannot present).
private let runsSDLWindowTest = ProcessInfo.processInfo.environment["SMK_RUN_SDL_WINDOW_TEST"] == "1"

/// Whether an SDL window here can present a frame. Not under SDL's `offscreen`
/// video driver, which MetalUI's Linux image sets: there `beginFrame()`
/// answers `nil`, so `drawFrameIfNeeded()` builds nothing (MetalUI
/// `SDLLifecycleTests`, record §76 §12). The test then proves only that the
/// app's `SDLPlatform` window opens with the app's themes and sizes.
private let windowsPresentFrames = ProcessInfo.processInfo.environment["SDL_VIDEO_DRIVER"] != "offscreen"

/// The shell -- `rootView(editor:)` -- in a hidden `SDLPlatform` window, built
/// the way `main.swift`'s `makeApp()` builds it off macOS (the portable text
/// system over the platform's fonts, the monospaced family registered),
/// walked through every rail mode, both macro sub-states and both colour
/// schemes. Where the window presents frames, every walk step draws one:
/// that covers the app's themes, the window-stamped scheme, the drawn
/// toolbar strip and the lifecycle drain on SDL. A layout refusal traps the
/// process.
@MainActor
@Suite("The shell draws in an SDL window", .serialized, .enabled(if: runsSDLWindowTest))
struct SDLWindowTests {
    @Test("every rail mode, both macro sub-states, light and dark, in an SDLPlatform window")
    func everyModeDrawsInAnSDLWindow() throws {
        let defaults = UserDefaults(suiteName: "SDLWindowTests-\(UUID().uuidString)")!
        let editor = EditorState(userDefaults: defaults)
        let resolver = try SystemFonts.resolver()
        #if os(Windows)
        resolver.register(design: .monospaced, family: "Consolas")
        #else
        resolver.register(design: .monospaced, family: "DejaVu Sans Mono")
        #endif
        let app = App(platform: try SDLPlatform(hiddenWindows: true),
                      textSystem: { PortableTextSystem(resolver: resolver) })
        ChromeTheme.apply(to: app)
        let window = try app.openWindow(
            title: "SDLWindowTests",
            size: WindowMetrics.idealSize,
            minSize: WindowMetrics.minSize,
            startsDisplayLink: false
        ) {
            rootView(editor: editor)
        }

        var draws = 0
        func draw() {
            window.setNeedsRedraw()
            window.drawFrameIfNeeded()
            draws += 1
        }
        let framesBefore = window.framesDrawn
        for scheme in [ColorScheme.light, ColorScheme.dark] {
            window.preferredColorScheme = scheme
            for mode in RailMode.allCases {
                editor.railMode = mode
                draw()
            }
            editor.railMode = .macros
            editor.createMacro()
            editor.appendStep(MacroStepType.keystroke.makeStep())
            editor.appendStep(MacroStepType.delay.makeStep())
            #expect(editor.macroWorkspace != .library)
            draw()
            editor.closeMacro()
            draw()
            if windowsPresentFrames {
                #expect(window.colorScheme == scheme)
            }
        }
        let framesDrawn = window.framesDrawn - framesBefore
        print("SDLWindowTests: \(draws) draws requested, \(framesDrawn) frames drawn, "
              + "SDL_VIDEO_DRIVER=\(ProcessInfo.processInfo.environment["SDL_VIDEO_DRIVER"] ?? "(unset)")")
        if windowsPresentFrames {
            #expect(framesDrawn == draws)
        }
        #expect(editor.railMode == .macros)
    }
}
#endif
