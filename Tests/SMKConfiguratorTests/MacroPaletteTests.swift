import Testing
@testable import SMKConfigurator

@Suite("Saved macros in the palette drawer")
@MainActor
struct MacroPaletteTests {
    @Test("the palette offers one macro token per saved macro")
    func paletteListsMacros() {
        var doc = KeymapDocument(
            matrix: .init(rows: [0], cols: [1], colsAreDriven: 1),
            layers: [[["none"]]]
        )
        doc.macros = [
            MacroDefinition(id: 0, name: "a", steps: []),
            MacroDefinition(id: 4, name: "b", steps: []),
        ]
        #expect(PaletteDrawerView.macroTokens(for: doc) == [.macro(0), .macro(4)])
    }

    @Test("the MACROS section height doesn't grow with the macro count")
    func macroSectionHeightIsFixed() {
        // PaletteDrawerView's height math is static and feeds
        // ContentView.minWindowHeight. If this section grew with the
        // document, the window's minimum height would depend on how many
        // macros the user owns.
        var few = KeymapDocument(
            matrix: .init(rows: [0], cols: [1], colsAreDriven: 1),
            layers: [[["none"]]]
        )
        few.macros = [MacroDefinition(id: 0, name: "a", steps: [])]

        var many = few
        many.macros = (0..<40).map { MacroDefinition(id: $0, name: "m\($0)", steps: []) }

        // The height is a `static let` taking no document, so it cannot vary
        // with content — this asserts it exists and is sane, while the token
        // counts below confirm the content really does vary.
        #expect(PaletteDrawerView.macroSectionHeight > 0)
        #expect(PaletteDrawerView.macroTokens(for: many).count == 40)
        #expect(PaletteDrawerView.macroTokens(for: few).count == 1)
    }
}
