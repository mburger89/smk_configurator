import Foundation
import Testing
@testable import SMKConfigurator

@Suite("KeyboardDesign matches the physical gateron_lp_kbd shape and round-trips as JSON")
struct KeyboardDesignTests {
    @Test("gateronLPKBD is 5x12 with a 2U key at row 4 col 5 and a gap at row 4 col 6")
    func gateronShapeMatchesHardware() {
        let design = KeyboardDesign.gateronLPKBD
        #expect(design.rowCount == 5)
        #expect(design.colCount == 12)

        for r in 0..<design.rowCount {
            for c in 0..<design.colCount {
                let cell = design.grid[r][c]
                if r == 4 && c == 6 {
                    #expect(cell.isGap)
                } else if r == 4 && c == 5 {
                    #expect(!cell.isGap)
                    #expect(cell.width == 2.0)
                } else {
                    #expect(!cell.isGap)
                    #expect(cell.width == 1.0)
                }
            }
        }

        let physicalKeyCount = design.grid.flatMap { $0 }.filter { !$0.isGap }.count
        #expect(physicalKeyCount == 59)
    }

    @Test("JSON round-trip preserves shape and matrix")
    func jsonRoundTrip() throws {
        let design = KeyboardDesign.gateronLPKBD
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(design)
        let decoded = try decoder.decode(KeyboardDesign.self, from: data)
        #expect(decoded == design)
    }

    @Test("genericGrid fallback is a uniform 1U grid with no gaps at the given dimensions")
    func genericGridFallback() {
        let matrix = KeymapDocument.Matrix(rows: [0, 1, 2], cols: [0, 1], colsAreDriven: 0)
        let design = KeyboardDesign.genericGrid(matrix: matrix)
        #expect(design.rowCount == 3)
        #expect(design.colCount == 2)
        #expect(design.grid.flatMap { $0 }.allSatisfy { !$0.isGap && $0.width == 1.0 })
    }
}
