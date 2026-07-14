import Foundation

/// A physical keyboard layout: a rectangular row/col grid (matching
/// `layers[layer][row][col]` in keymap.json) where each cell is either a key
/// of some width (in 1U keycap units) or a gap (no physical switch there),
/// plus the matrix electrical config (`matrix.rows`/`matrix.cols` GPIO
/// numbers, `colsAreDriven`) needed to write a valid `keymap.json` for it.
///
/// This is purely an editor-side concept -- the firmware only ever reads
/// `KeymapDocument`, which doesn't carry key widths/gaps at all.
struct KeyboardDesign: Codable, Equatable, Identifiable {
    struct Cell: Codable, Equatable {
        var width: Double = 1.0
        var isGap: Bool = false
    }

    var name: String
    var matrix: KeymapDocument.Matrix
    /// `grid.count == matrix.rows.count`; every `grid[r].count == matrix.cols.count`.
    var grid: [[Cell]]

    var id: String { name }
    var rowCount: Int { matrix.rows.count }
    var colCount: Int { matrix.cols.count }

    struct Slot: Identifiable {
        var row: Int
        var col: Int
        var widthUnits: Double
        var id: String { "\(row),\(col)" }
    }

    /// The non-gap slots in row `r`, left to right. Shared by every board
    /// renderer (`KeyboardBoardView`, `ThemePreviewBoardView`) so gaps are
    /// skipped consistently -- a placeholder child there would get `HStack`
    /// spacing on both sides and double the gap.
    func visibleSlots(row r: Int) -> [Slot] {
        (0..<colCount).compactMap { c in
            let cell = grid[r][c]
            guard !cell.isGap else { return nil }
            return Slot(row: r, col: c, widthUnits: cell.width)
        }
    }

    /// The bundled default: gateron_lp_kbd (`~/esp/SMK_Keyboard`), 5x12,
    /// row 4 col 5 is a 2U key, row 4 col 6 has no switch. Matches
    /// `generate_kbd.py`'s `KEYS`/`key_pos` and the GPIO map documented in
    /// `~/esp/SMK/CLAUDE.md`.
    static let gateronLPKBD: KeyboardDesign = {
        let matrix = KeymapDocument.Matrix(
            rows: [0, 1, 2, 3, 5],
            cols: [6, 7, 8, 14, 15, 18, 19, 20, 21, 22, 23, 17],
            colsAreDriven: 1
        )
        let grid: [[Cell]] = (0..<matrix.rows.count).map { r in
            (0..<matrix.cols.count).map { c in
                if r == 4 && c == 6 {
                    return Cell(width: 1.0, isGap: true)
                }
                let width: Double = (r == 4 && c == 5) ? 2.0 : 1.0
                return Cell(width: width, isGap: false)
            }
        }
        return KeyboardDesign(name: "gateron_lp_kbd", matrix: matrix, grid: grid)
    }()

    /// Fallback for a `keymap.json` whose matrix doesn't match any known
    /// design: a plain uniform 1U grid at the file's own dimensions, so it
    /// still renders instead of failing to load.
    static func genericGrid(matrix: KeymapDocument.Matrix, name: String = "Unknown board") -> KeyboardDesign {
        let grid: [[Cell]] = (0..<matrix.rows.count).map { _ in
            (0..<matrix.cols.count).map { _ in Cell() }
        }
        return KeyboardDesign(name: name, matrix: matrix, grid: grid)
    }

    /// A minimal starting point for the "New Design" flow.
    static func blank(name: String = "New Design") -> KeyboardDesign {
        KeyboardDesign(
            name: name,
            matrix: KeymapDocument.Matrix(rows: [0], cols: [0], colsAreDriven: 1),
            grid: [[Cell()]]
        )
    }
}
