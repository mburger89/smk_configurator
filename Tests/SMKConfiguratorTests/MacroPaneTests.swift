import Foundation
import MetalUI
import MetalUIPortableText
import MetalUISystemFonts
import Testing
@testable import SMKConfigurator

/// MACROS mode's panes (port plan §1.9–§1.10) built, laid out and drawn
/// headlessly in the states a shell walk does not reach -- an empty library, a
/// filtered-out library, a disabled-and-bound macro with its warning, a library
/// over capacity, every step type in the inspector, every inspector tab --
/// through MetalUI's public API only. A layout refusal traps, so passing means
/// "builds and lays out"; nothing here sees whether it looks right (gap MG-12).
@MainActor
@Suite("The MACROS panes build in their edge states", .serialized)
struct MacroPaneRenderTests {
    private let textSystem: PortableTextSystem
    private let atlas = GlyphAtlas(width: 2048, height: 2048)

    init() throws {
        textSystem = PortableTextSystem(resolver: try SystemFonts.resolver())
    }

    private func makeEditor() -> EditorState {
        EditorState(userDefaults: UserDefaults(suiteName: "MacroPaneRenderTests-\(UUID().uuidString)")!)
    }

    private func render<Pane: ElementGroup>(_ name: String, _ pane: @escaping @MainActor () -> Pane) {
        let scene = renderFrame({ Row { pane() } }, size: WindowMetrics.idealSize, scaleFactor: 2,
                                textSystem: textSystem, atlas: atlas)
        #expect(!scene.glyphs.isEmpty, "\(name): no glyphs")
    }

    @Test("library: empty, then macros with a disabled-and-bound one, then over capacity")
    func library() throws {
        let editor = makeEditor()
        editor.railMode = .macros
        render("library, no macros") { MacroLibraryView(editor: editor) }

        editor.createMacro()
        editor.appendStep(MacroStepType.text.makeStep())
        editor.closeMacro()
        editor.createMacro()
        editor.closeMacro()
        let ids = editor.document.macroList.map(\.id)
        try #require(ids.count == 2)
        editor.assign(.macro(ids[0]), row: 0, col: 0)
        editor.setMacroEnabled(id: ids[0], false)
        editor.setMacroCollection(id: ids[1], "Work stuff")
        let warned = MacroLibraryRow(macro: editor.document.macroList[0], document: editor.document)
        try #require(warned.disabledWarning != nil)
        render("library, a disabled bound macro") { MacroLibraryView(editor: editor) }

        editor.openMacro(id: ids[1])
        editor.appendStep(.text(String(repeating: "overflow ", count: 600), delivery: .keystrokes, msPerChar: 10))
        editor.closeMacro()
        try #require(editor.macroBudget.blockReason != nil)
        render("library, over capacity") { MacroLibraryView(editor: editor) }
    }

    @Test("step editor: palette column, canvas header, step rows of every type")
    func stepEditor() {
        let editor = makeEditor()
        editor.railMode = .macros
        editor.createMacro()
        for type in MacroStepType.allCases {
            editor.appendStep(type.makeStep())
        }
        editor.appendStep(.raw(.object(["op": .string("xyz")])))
        render("palette column") { MacroStepPaletteView(editor: editor) }
        render("canvas header") { MacroCanvasHeaderView(editor: editor) }
        let steps = editor.currentMacro?.steps ?? []
        #expect(steps.count == MacroStepType.allCases.count + 1)
        for (index, step) in steps.enumerated() {
            render("step row \(index)") {
                MacroStepRowView(step: step, index: index, isSelected: index == 0,
                                 onSelect: {}, onMoveUp: {}, onMoveDown: {}, onDelete: {})
            }
        }
    }

    @Test("inspector: every tab, every step type selected, MO(0), a repeat block with contents")
    func inspector() {
        let editor = makeEditor()
        editor.railMode = .macros
        editor.createMacro()
        for type in MacroStepType.allCases {
            editor.appendStep(type.makeStep())
        }
        editor.appendStep(.layer(op: .momentary, n: 0))
        editor.appendStep(.repeatBlock(count: 3, steps: [MacroStepType.keystroke.makeStep(),
                                                         MacroStepType.delay.makeStep()]))
        editor.appendStep(.raw(.object(["op": .string("xyz")])))
        editor.appendStep(.keystroke(mods: [], key: nil, holdMs: 40))
        let count = editor.currentMacro?.steps.count ?? 0
        #expect(count == MacroStepType.allCases.count + 4)

        editor.selectedStepIndex = nil
        render("inspector, nothing selected") { MacroInspectorView(editor: editor) }
        for index in 0..<count {
            editor.selectedStepIndex = index
            render("inspector, step \(index)") { MacroInspectorView(editor: editor) }
        }
        for tab in MacroInspectorTab.allCases {
            editor.macroInspectorTab = tab
            render("inspector, \(tab) tab") { MacroInspectorView(editor: editor) }
        }
    }
}

/// The MACROS panes' view-level logic: the step-type drag payload, the slider
/// adapters, and the MO(0) rule.
@MainActor
@Suite("MACROS pane logic")
struct MacroPaneLogicTests {
    @Test("every step type survives the drag payload round trip")
    func dragPayloadRoundTrip() {
        for type in MacroStepType.allCases {
            #expect(MacroStepDrop.type(from: [MacroStepDrop.payload(for: type)]) == type)
        }
    }

    @Test("text dragged in from another app is refused; the first step type wins")
    func dragPayloadRefusesText() {
        #expect(MacroStepDrop.type(from: ["hello", "macro:1"]) == nil)
        #expect(MacroStepDrop.type(from: []) == nil)
        #expect(MacroStepDrop.type(from: ["hello", "delay", "text"]) == .delay)
    }

    @Test("dropping a step type on the card appends it and marks the document dirty")
    func dropAppends() throws {
        let editor = EditorState(userDefaults: UserDefaults(suiteName: "MacroPaneLogicTests-\(UUID().uuidString)")!)
        editor.createMacro()
        editor.isDirty = false
        let type = try #require(MacroStepDrop.type(from: [MacroStepDrop.payload(for: .layer)]))
        editor.appendStep(type.makeStep())
        #expect(editor.currentMacro?.steps.last == MacroStepType.layer.makeStep())
        #expect(editor.isDirty)
    }

    @Test("the millisecond slider writes whole 10 ms ticks, rounding up")
    func millisecondAdapterQuantises() {
        var written: [Int] = []
        let binding = SliderAdapter.milliseconds(40) { written.append($0) }
        #expect(binding.wrappedValue == 40)
        binding.wrappedValue = 47
        binding.wrappedValue = 50
        binding.wrappedValue = 50.6
        #expect(written == [50, 50, 60])
    }

    @Test("the count slider writes the nearest whole number")
    func countAdapterRounds() {
        var written: [Int] = []
        let binding = SliderAdapter.count(3) { written.append($0) }
        #expect(binding.wrappedValue == 3)
        binding.wrappedValue = 4.4
        binding.wrappedValue = 4.6
        #expect(written == [4, 5])
    }

    @Test("only momentary layer 0 is flagged dead")
    func deadMomentaryZero() {
        #expect(MacroStepEditor.isDeadMomentaryZero(op: .momentary, n: 0))
        #expect(!MacroStepEditor.isDeadMomentaryZero(op: .toggle, n: 0))
        #expect(!MacroStepEditor.isDeadMomentaryZero(op: .momentary, n: 1))
    }
}
