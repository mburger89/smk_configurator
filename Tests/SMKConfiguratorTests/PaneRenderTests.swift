import Foundation
import MetalUI
import MetalUIPortableText
import MetalUISystemFonts
import Testing
@testable import SMKConfigurator

/// Builds, lays out and draws the KEY, DSN, THM and DEV panes in the states a
/// shell walk does not reach -- Advanced Mode, a selected DSN cell, an invalid
/// theme hex, a full MACROS strip, an upload in progress, no inspected key --
/// through MetalUI's public API only. A layout refusal traps, so passing means
/// "builds and lays out"; it cannot see whether anything looks right (gap
/// MG-12: no layout read-back, light scheme only headless).
@MainActor
@Suite("The KEY, DSN, THM and DEV panes build in their edge states", .serialized)
struct PaneRenderTests {
    private let textSystem: PortableTextSystem
    private let atlas = GlyphAtlas(width: 2048, height: 2048)

    init() throws {
        textSystem = PortableTextSystem(resolver: try SystemFonts.resolver())
    }

    private func makeEditor() -> EditorState {
        EditorState(userDefaults: UserDefaults(suiteName: "PaneRenderTests-\(UUID().uuidString)")!)
    }

    /// Renders `pane` alone in a window-sized frame and checks it drew text.
    private func render<Pane: ElementGroup>(_ name: String, _ pane: @escaping @MainActor () -> Pane) {
        let scene = renderFrame({ Row { pane() } }, size: WindowMetrics.idealSize, scaleFactor: 2,
                                textSystem: textSystem, atlas: atlas)
        #expect(!scene.glyphs.isEmpty, "\(name): no glyphs")
    }

    @Test("KEY: Advanced Mode, a full MACROS strip, many layers, no inspected key")
    func keyPanes() {
        let editor = makeEditor()
        for _ in 0..<(PaletteLayout.chipsPerRow + 2) {
            editor.createMacro()
        }
        editor.closeMacro()
        while editor.document.layers.count < EditorState.maxLayerCount {
            editor.addLayer()
        }
        editor.pendingLayerIndex = editor.maxAssignableLayerIndex
        editor.assign(PaletteLayout.macroTokens(for: editor.document)[0], row: 0, col: 0)
        for advanced in [false, true] {
            editor.setShowAdvanced(advanced)
            render("key list") { KeyListColumnView(editor: editor, selectDesign: { _ in }, selectTheme: { _ in }) }
            render("key main") { KeyMainContentView(editor: editor) }
            render("key inspector") { KeyInspectorView(editor: editor) }
        }
        editor.selectedKeyPosition = nil
        render("key inspector, nothing inspected") { KeyInspectorView(editor: editor) }
        editor.selectedKeyPosition = KeyPosition(row: 99, col: 99)
        render("key inspector, stale position") { KeyInspectorView(editor: editor) }
    }

    @Test("DSN: no selection, a selected key cell, a selected gap, an unsaved draft")
    func designPanes() {
        let editor = makeEditor()
        let draft = editor.activeDesign
        for selection in [nil, DesignGridPosition(row: 0, col: 0), DesignGridPosition(row: 4, col: 6)] {
            render("dsn grid") {
                DesignGridEditorView(draft: .constant(draft), selectedCell: .constant(selection))
            }
        }
        render("dsn list") {
            DesignListColumnView(editor: editor, draft: .constant(draft), selectDesign: { _ in }, newDesign: {})
        }
        render("dsn inspector") {
            DesignInspectorView(draft: .blank(), isExistingDesign: false, save: {}, duplicate: {}, delete: {})
        }
    }

    @Test("THM: an invalid hex in the draft, the live preview")
    func themePanes() {
        let editor = makeEditor()
        var draft = editor.activeTheme
        draft.keyBackground = ThemeColor(hex: "#12")
        let theme = draft
        render("thm list") {
            ThemeListColumnView(editor: editor, draft: .constant(theme), selectTheme: { _ in }, newTheme: {})
        }
        render("thm main") { ThemeMainContentView(editor: editor, draft: theme) }
        render("thm inspector") {
            ThemeInspectorView(draft: theme, save: {}, duplicate: {}, importTheme: {}, exportTheme: {})
        }
    }

    @Test("DEV: idle, then sending with progress and a last-sent time")
    func devicePanes() {
        let editor = makeEditor()
        render("dev list") { DeviceListColumnView(editor: editor) }
        render("dev main") { DeviceMainContentView(editor: editor) }
        editor.usbConnected = true
        editor.isSendingToDevice = true
        editor.uploadProgress = .chunk(index: 2, of: 9)
        editor.lastSentAt = Date().addingTimeInterval(-90)
        render("dev main, sending") { DeviceMainContentView(editor: editor) }
        render("dev inspector") { DeviceInspectorView(editor: editor) }
    }
}
