import Testing
@testable import SMKConfigurator

@Suite("Macro library rows")
struct MacroLibraryRowTests {
    private func document(macros: [MacroDefinition], cell: String = "none") -> KeymapDocument {
        KeymapDocument(
            matrix: .init(rows: [0], cols: [1], colsAreDriven: 1),
            layers: [[[cell]]],
            macros: macros)
    }

    @Test("a row carries the macro's enabled flag and collection")
    func rowCarriesFields() {
        let macro = MacroDefinition(id: 0, name: "A", steps: [],
                                    enabled: false, collection: "Work")
        let row = MacroLibraryRow(macro: macro, document: document(macros: [macro]))
        #expect(row.isEnabled == false)
        #expect(row.collection == "Work")
    }

    @Test("a disabled but bound macro warns and names the key")
    func disabledBoundMacroWarns() throws {
        let macro = MacroDefinition(id: 0, name: "A", steps: [], enabled: false)
        let row = MacroLibraryRow(macro: macro,
                                  document: document(macros: [macro], cell: "macro:0"))
        let warning = try #require(row.disabledWarning)
        #expect(warning.contains("R0C0"))
        #expect(warning.contains("Layer 0"))
    }

    @Test("a disabled unbound macro has nothing to warn about")
    func disabledUnboundMacroIsQuiet() {
        let macro = MacroDefinition(id: 0, name: "A", steps: [], enabled: false)
        #expect(MacroLibraryRow(macro: macro, document: document(macros: [macro]))
            .disabledWarning == nil)
    }

    @Test("an enabled bound macro has nothing to warn about")
    func enabledBoundMacroIsQuiet() {
        let macro = MacroDefinition(id: 0, name: "A", steps: [])
        #expect(MacroLibraryRow(macro: macro,
                                document: document(macros: [macro], cell: "macro:0"))
            .disabledWarning == nil)
    }

    @Test("search text covers the name and every step, including nested ones")
    func searchTextCoversSteps() {
        let macro = MacroDefinition(id: 0, name: "Sign off", steps: [
            .repeatBlock(count: 2, steps: [
                .text("regards", delivery: .keystrokes, msPerChar: 10)
            ])
        ])
        let text = MacroLibraryRow(macro: macro, document: document(macros: [macro])).searchText
        // Lowercased once at construction (so the filter needn't re-lowercase
        // it per keystroke), which is why the name is matched here in the
        // folded form the filter will actually compare against.
        #expect(text == text.lowercased())
        #expect(text.contains("sign off"))
        #expect(text.contains("regards"))
    }
}
