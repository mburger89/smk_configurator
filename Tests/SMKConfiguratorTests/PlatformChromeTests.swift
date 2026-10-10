import Foundation
import MetalUI
import MetalUIPortableText
import MetalUISystemFonts
import Testing
@testable import SMKConfigurator

/// The app's platform chrome (cross-platform plan §1.1 A6/A7, §1.2 M1): the
/// primary shortcut modifier (gap MG-24), and the File menu and the
/// Linux/Windows toolbar both read from `FileCommand.all` (gap MG-23).
///
/// The menu and the toolbar are read where a platform receives them: a
/// headless fake `Platform` (below) records `setMenuBar` and `setToolbar`,
/// answers `false` to `setToolbar` as SDL does -- so MetalUI lays out and
/// draws its toolbar strip -- and presents every frame. No GPU, no SDL, no
/// AppKit window, so it runs on all three platforms (and is the only place
/// the strip is laid out under the offscreen SDL driver, which presents no
/// frame: `SDLWindowTests`).
@MainActor
@Suite("Menu, toolbar and shortcuts come from one table", .serialized)
struct PlatformChromeTests {
    @Test("the primary shortcut modifier is ⌘ on macOS and Ctrl elsewhere")
    func primaryModifierPerPlatform() {
        #if os(macOS)
        #expect(primaryShortcutModifier == .command)
        #else
        #expect(primaryShortcutModifier == .control)
        #endif
    }

    @Test("the file-command table: six entries, the File menu's order, primary shortcuts")
    func fileCommandTable() {
        let commands = FileCommand.all
        #expect(commands.map(\.title) == ["New", "Open…", "Save", "Save As…", "Import…", "Export…"])
        #expect(commands.map(\.icon) == [.newDoc, .open, .save, .saveAs, .importFile, .exportFile])
        #expect(commands.map(\.startsGroup) == [false, false, true, false, true, false])
        #expect(commands.map(\.shortcut) == [
            KeyboardShortcut("n", modifiers: primaryShortcutModifier),
            KeyboardShortcut("o", modifiers: primaryShortcutModifier),
            KeyboardShortcut("s", modifiers: primaryShortcutModifier),
            KeyboardShortcut("s", modifiers: [primaryShortcutModifier, .shift]),
            nil, nil,
        ])
        #if os(macOS)
        #expect(commands[3].helpText == "Save As (⌘+Shift+S)")
        #else
        #expect(commands[3].helpText == "Save As (Ctrl+Shift+S)")
        #endif
        #expect(commands[4].helpText == "Import")
    }

    @Test("the File menu the platform receives is the table, in order, with its shortcuts and dividers")
    func menuBarReadsTheTable() throws {
        let harness = try ChromeHarness()
        let bar = try #require(harness.platform.menuBars.last)
        let file = try #require(bar.content().first { menu in menu.items.contains { $0.title == "New" } })
        let start = try #require(file.items.firstIndex { $0.title == "New" })
        let ours = Array(file.items[start...].prefix(FileCommand.all.count + 2))
        var expected: [String] = []
        var expectedShortcuts: [PlatformKeyEquivalent?] = []
        for command in FileCommand.all {
            if command.startsGroup { expected.append("—"); expectedShortcuts.append(nil) }
            expected.append(command.title)
            expectedShortcuts.append(command.shortcut.map {
                PlatformKeyEquivalent(key: String($0.key.character), modifiers: $0.modifiers)
            })
        }
        #expect(ours.map { $0.kind == .separator ? "—" : $0.title } == expected)
        #expect(ours.map(\.shortcut) == expectedShortcuts)
    }

    @Test("the toolbar the platform receives is the table's six buttons, then Advanced and Appearance")
    func toolbarReadsTheTable() throws {
        let harness = try ChromeHarness()
        harness.draw()
        let toolbar = try #require(harness.platform.lastWindow?.toolbars.last ?? nil)
        let ids = FileCommand.all.map(\.toolbarID) + ["view.advanced", "view.appearance"]
        #expect(toolbar.items.map(\.id) == ids)
        for (item, command) in zip(toolbar.items, FileCommand.all) {
            guard case .button(let title, let image) = item.control else {
                Issue.record("\(item.id) is not a button: \(item.control)")
                continue
            }
            #expect(title == command.plainTitle)
            #expect(image != nil, "\(item.id) draws its icon")
            #expect(item.placement == .navigation)
            #expect(item.help == command.helpText)
        }
        #expect(toolbar.items[6].control == .toggle(title: "Advanced", isOn: harness.editor.showAdvanced))
        let selected = AppearanceMode.allCases.firstIndex(of: harness.editor.appearanceMode)
        #expect(toolbar.items[7].control == .picker(title: "Appearance", options: ["Light", "Dark", "System"],
                                                    selected: selected, style: .menu))
    }

    @Test("the drawn strip lays out, and its first button runs New")
    func theStripsNewButtonRunsTheCommand() throws {
        let harness = try ChromeHarness()
        harness.draw()
        harness.editor.fileURL = URL(fileURLWithPath: "/tmp/PlatformChromeTests.json")
        // The strip's leading item: 8 points of padding, then the New button,
        // centred in the 38-point bar.
        let point = Point(x: Pixels(20), y: Pixels(19))
        harness.input(.mouseMoved(MouseEvent(position: point)))
        harness.input(.mouseDown(MouseEvent(position: point)))
        harness.input(.mouseUp(MouseEvent(position: point)))
        #expect(harness.editor.fileURL == nil, "New cleared the file")
    }

    @Test("the toolbar's Advanced and Appearance write the model")
    func toolbarControlsWriteTheModel() throws {
        let harness = try ChromeHarness()
        harness.draw()
        let before = harness.editor.showAdvanced
        harness.input(.toolbarAction(ToolbarActionEvent(item: "view.advanced",
                                                                             action: .toggle(!before))))
        #expect(harness.editor.showAdvanced == !before)
        let dark = try #require(AppearanceMode.allCases.firstIndex(of: .dark))
        harness.input(.toolbarAction(ToolbarActionEvent(item: "view.appearance",
                                                                             action: .select(dark))))
        #expect(harness.editor.appearanceMode == .dark)
    }

    @Test("the primary modifier + N runs New; ⌘N does not off macOS")
    func primaryShortcutRunsNew() throws {
        let harness = try ChromeHarness()
        harness.draw()
        func press(_ modifiers: Modifiers) {
            let key = KeyEvent(charactersIgnoringModifiers: "n", characters: "n", modifiers: modifiers, timestamp: 0)
            harness.input(.keyDown(key))
            harness.input(.keyUp(key))
        }
        #if !os(macOS)
        harness.editor.fileURL = URL(fileURLWithPath: "/tmp/PlatformChromeTests.json")
        press(.command)
        #expect(harness.editor.fileURL != nil, "Super+N is not the app's shortcut")
        #endif
        harness.editor.fileURL = URL(fileURLWithPath: "/tmp/PlatformChromeTests.json")
        press(primaryShortcutModifier)
        #expect(harness.editor.fileURL == nil, "the primary modifier + N ran New")
    }
}

// MARK: - Harness

/// The app's window over `ChromeFakePlatform`, built as `main.swift` builds it:
/// the themes, the commands, the root -- and on macOS, where `ContentView`
/// compiles its toolbar out, the same toolbar applied by hand so the table's
/// toolbar half is checked there too.
@MainActor
private final class ChromeHarness {
    let platform = ChromeFakePlatform()
    let editor: EditorState
    let app: App
    var window: Window!

    init() throws {
        editor = EditorState(userDefaults: UserDefaults(suiteName: "PlatformChromeTests-\(UUID().uuidString)")!)
        let resolver = try SystemFonts.resolver()
        app = App(platform: platform, textSystem: { PortableTextSystem(resolver: resolver) })
        ChromeTheme.apply(to: app)
        let editor = editor
        #if os(macOS)
        window = try app.openWindow(title: "PlatformChromeTests", size: WindowMetrics.idealSize,
                                    minSize: WindowMetrics.minSize, startsDisplayLink: false) {
            Column {
                ToolbarByHand(editor: editor)
            }
            .frame(maxWidth: Pixels(.infinity), maxHeight: Pixels(.infinity))
        }
        #else
        window = try app.openWindow(title: "PlatformChromeTests", size: WindowMetrics.idealSize,
                                    minSize: WindowMetrics.minSize, startsDisplayLink: false) {
            rootView(editor: editor)
        }
        #endif
        installAppCommands(app: app, window: window, editor: editor)
    }

    /// Delivers `event` as the platform would.
    func input(_ event: InputEvent) {
        _ = platform.lastWindow?.onInput?(event)
    }

    /// One frame, and the settle frames a toolbar change asks for.
    func draw() {
        for _ in 0..<3 {
            window.setNeedsRedraw()
            window.drawFrameIfNeeded()
        }
    }
}

/// macOS only: `ContentView` with the toolbar `platformToolbar` compiles out
/// there, written as `ContentView` writes it on Linux and Windows.
@MainActor
private struct ToolbarByHand: Component {
    let editor: EditorState
    @Environment(\.fileDialogs) var dialogs

    var content: some ElementGroup {
        ContentView(editor: editor)
            .fileToolbar(editor: editor, dialogs: dialogs, colorScheme: .light)
    }
}

/// A headless `Platform`: records the menu bar, opens `ChromeFakeWindow`s.
@MainActor
private final class ChromeFakePlatform: Platform {
    private(set) var menuBars: [PlatformMenuBar] = []
    private(set) var lastWindow: ChromeFakeWindow?

    func openWindow(title: String, size: Size<Pixels>) throws -> any PlatformWindow {
        let window = ChromeFakeWindow(size: size)
        window.title = title
        lastWindow = window
        return window
    }

    func run() {}
    func setApplicationIcon(_ images: [ImageTexture]) {}
    func setMenuBar(_ menuBar: PlatformMenuBar) { menuBars.append(menuBar) }
}

/// Presents every frame it is asked for and draws nothing.
@MainActor
private final class ChromeFakeRenderer: WindowRenderer {
    private(set) var framesFinished = 0
    func beginFrame() -> Float? { 2 }
    func finishFrame(scene: Scene, atlas: GlyphAtlas, surfaces: [SurfaceDrawRequest]) -> Bool {
        framesFinished += 1
        return true
    }
}

/// A window that answers `false` to `setToolbar` (SDL's answer: the window
/// draws the strip), `false` to menus and alerts (drawn too), and records
/// every toolbar it is handed.
@MainActor
private final class ChromeFakeWindow: PlatformWindow {
    let fakeRenderer = ChromeFakeRenderer()
    var renderer: any WindowRenderer { fakeRenderer }
    var contentSize: Size<Pixels>
    var scaleFactor: Float = 2
    var title = ""
    var appearance: Appearance = .light
    var onInput: ((InputEvent) -> Bool)?
    var onResize: ((Size<Pixels>, Float) -> Void)?
    var onAppearanceChange: ((Appearance) -> Void)?
    var controlActiveState: ControlActiveState = .key
    var onControlActiveStateChange: ((ControlActiveState) -> Void)?
    var accessibilityReduceMotion = false
    var onAccessibilityReduceMotionChange: ((Bool) -> Void)?
    var onClose: (() -> Void)?
    var onAccessibilityRequest: ((AccessibilityRequest) -> Bool)?
    private(set) var toolbars: [PlatformToolbar?] = []
    private var clipboard: String?

    init(size: Size<Pixels>) { contentSize = size }

    func setPreferredColorScheme(_ colorScheme: ColorScheme?) {}
    func publishAccessibilityTree(_ tree: AccessibilityTree) {}
    func setTextInputArea(_ caret: Bounds<Pixels>?) {}
    func readClipboard() -> String? { clipboard }
    func writeClipboard(_ text: String) { clipboard = text }
    func startDisplayLink(_ tick: @escaping (Double) -> Void) {}
    func setDisplayLinkPaused(_ paused: Bool) {}
    func beginExternalDrag(_ representations: [DragRepresentation], at position: Point<Pixels>) -> Bool { false }
    func presentMenu(_ menu: PlatformMenu, at position: Point<Pixels>) -> Bool { false }
    func presentFileDialog(_ dialog: PlatformFileDialog) -> Bool { false }
    func presentAlert(_ alert: PlatformAlert) -> Bool { false }
    func dismissPresentation(token: Int) {}
    func setContentSizeLimits(minimum: Size<Pixels>?, maximum: Size<Pixels>?) {}
    func setToolbar(_ toolbar: PlatformToolbar?) -> Bool {
        toolbars.append(toolbar)
        return false
    }
}
