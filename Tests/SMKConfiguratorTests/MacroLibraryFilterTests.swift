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
        // Lowercased at construction so the filter can compare it against a
        // lowercased query without either side folding case again, which is
        // why the name is matched here in that folded form. (Not a
        // per-keystroke saving: `MacroLibraryView.rows` is computed, so every
        // row is rebuilt on each body evaluation anyway.)
        #expect(text == text.lowercased())
        #expect(text.contains("sign off"))
        #expect(text.contains("regards"))
    }
}

@Suite("Filtering the macro library")
struct MacroLibraryFilterTests {
    private func rows() -> [MacroLibraryRow] {
        let macros = [
            MacroDefinition(id: 0, name: "Sign off", steps: [
                .text("kind regards", delivery: .keystrokes, msPerChar: 10)
            ], collection: "Work"),
            MacroDefinition(id: 1, name: "Build", steps: [.delay(ms: 20)],
                            collection: "Dev"),
            MacroDefinition(id: 2, name: "Ungrouped one", steps: []),
        ]
        let document = KeymapDocument(
            matrix: .init(rows: [0], cols: [1], colsAreDriven: 1),
            layers: [[["none"]]],
            macros: macros)
        return macros.map { MacroLibraryRow(macro: $0, document: document) }
    }

    @Test("an empty filter keeps everything")
    func emptyFilterKeepsAll() {
        #expect(MacroLibraryFilter().apply(to: rows()).count == 3)
    }

    @Test("search matches the name, case-insensitively")
    func searchMatchesName() {
        var filter = MacroLibraryFilter()
        filter.query = "SIGN"
        #expect(filter.apply(to: rows()).map(\.id) == [0])
    }

    @Test("search matches step content, not just the name")
    func searchMatchesStepContent() {
        var filter = MacroLibraryFilter()
        filter.query = "regards"
        #expect(filter.apply(to: rows()).map(\.id) == [0])
    }

    @Test("whitespace-only search is treated as no search")
    func blankSearchKeepsAll() {
        var filter = MacroLibraryFilter()
        filter.query = "   "
        #expect(filter.apply(to: rows()).count == 3)
    }

    @Test("a collection filter keeps only that collection")
    func collectionFilters() {
        var filter = MacroLibraryFilter()
        filter.collection = "Dev"
        #expect(filter.apply(to: rows()).map(\.id) == [1])
    }

    @Test("search and collection combine")
    func filtersCombine() {
        var filter = MacroLibraryFilter()
        filter.collection = "Work"
        filter.query = "build"
        #expect(filter.apply(to: rows()).isEmpty)
    }
}
