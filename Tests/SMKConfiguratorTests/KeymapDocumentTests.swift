import Foundation
import Testing
@testable import SMKConfigurator

@Suite("KeymapDocument round-trips the real keymap.json losslessly")
struct KeymapDocumentTests {
    @Test("decode -> encode -> decode is structurally stable")
    func roundTripsRealFile() throws {
        guard let data = try? Data(contentsOf: defaultKeymapURL) else {
            // ~/esp/SMK/keymap.json isn't present in this environment; skip.
            return
        }

        let decoder = JSONDecoder()
        let first = try decoder.decode(KeymapDocument.self, from: data)

        let encoder = JSONEncoder()
        let reEncoded = try encoder.encode(first)
        let second = try decoder.decode(KeymapDocument.self, from: reEncoded)

        #expect(first == second)
        #expect(first.matrix.rows == [0, 1, 2, 3, 5])
        #expect(first.matrix.cols.count == 12)
        #expect(first.layers.first?.count == 5)
    }

    @Test("blank(for:) matches the design's matrix and full grid size (gaps included)")
    func blankMatchesPhysicalLayout() {
        let design = KeyboardDesign.gateronLPKBD
        let doc = KeymapDocument.blank(for: design)
        #expect(doc.matrix == design.matrix)
        #expect(doc.layers.count == 1)
        let filled = doc.layers[0].flatMap { $0 }.count
        #expect(filled == design.rowCount * design.colCount)
    }

    @Test("renumberLayerReferences shifts references above the removed layer down")
    func renumberShiftsHigherReferences() {
        var doc = KeymapDocument(
            matrix: .init(rows: [0], cols: [0, 1, 2, 3], colsAreDriven: 0),
            layers: [
                [["mo:1", "tg:3", "mo:5", "key:a"]],
                [["trans", "mo:2", "tg:2", "custom:thing"]],
            ]
        )
        // Deleting layer 2: 1 stays, 2 dangles, 3 and 5 shift down.
        doc.renumberLayerReferences(afterRemoving: 2)
        #expect(doc.layers[0][0] == ["mo:1", "tg:2", "mo:4", "key:a"])
        #expect(doc.layers[1][0] == ["trans", "none", "none", "custom:thing"])
    }

    @Test("renumberLayerReferences leaves everything below the removed layer alone")
    func renumberLeavesLowerReferencesAlone() {
        var doc = KeymapDocument(
            matrix: .init(rows: [0], cols: [0, 1, 2], colsAreDriven: 0),
            layers: [[["mo:0", "tg:1", "none"]]]
        )
        let before = doc.layers
        doc.renumberLayerReferences(afterRemoving: 4)
        #expect(doc.layers == before)
    }

    @Test("reshaped(to:) preserves overlapping cells and pads new ones with none")
    func reshapeGrowsAndShrinks() {
        let small = KeyboardDesign.blank(name: "small")
        var layer = [["key:a"]]

        let grown = layer.reshaped(to: KeyboardDesign.genericGrid(
            matrix: .init(rows: [0, 1], cols: [0, 1], colsAreDriven: 0)
        ))
        #expect(grown == [["key:a", "none"], ["none", "none"]])

        layer = [["key:a", "key:b"], ["key:c", "key:d"]]
        let shrunk = layer.reshaped(to: small)
        #expect(shrunk == [["key:a"]])
    }
}
