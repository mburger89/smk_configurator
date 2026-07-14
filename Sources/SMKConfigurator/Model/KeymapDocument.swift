import Foundation

/// Mirrors the `keymap.json` schema read by `LayerEngine.loadKeymap` in the
/// SMK firmware (`~/esp/SMK/Sources/smk/LayerEngine.swift`). Cells are kept
/// as raw strings rather than a parsed enum so save is always lossless, even
/// for tokens this app's UI doesn't specifically know how to render.
struct KeymapDocument: Codable, Equatable {
    struct Matrix: Codable, Equatable {
        var rows: [Int]
        var cols: [Int]
        var colsAreDriven: Int
    }

    var matrix: Matrix
    /// layer -> row -> col -> raw action string (e.g. "key:a", "mod:leftShift", "mo:1", "trans", "none")
    var layers: [[[String]]]

    /// A fresh, empty keymap sized for `design`: one layer, every cell
    /// (including gaps, which the firmware never reads since no switch
    /// exists there) set to "none". Keeping a full rectangular grid, gaps
    /// included, keeps row/col indexing simple.
    static func blank(for design: KeyboardDesign) -> KeymapDocument {
        let layer = (0..<design.rowCount).map { _ in
            (0..<design.colCount).map { _ in "none" }
        }
        return KeymapDocument(matrix: design.matrix, layers: [layer])
    }

    /// A new layer defaulting every cell to "trans" (fall through to the
    /// layer below), matching the convention already used by layer 1 in
    /// `~/esp/SMK/keymap.json`.
    static func blankTransparentLayer(for design: KeyboardDesign) -> [[String]] {
        (0..<design.rowCount).map { _ in
            (0..<design.colCount).map { _ in "trans" }
        }
    }
}

extension Array where Element == [String] {
    /// Reshapes a layer (row -> col -> raw action string) to match `design`'s
    /// dimensions: overlapping cells keep their value, new cells default to
    /// "none", extra rows/cols are dropped.
    func reshaped(to design: KeyboardDesign) -> [[String]] {
        (0..<design.rowCount).map { r in
            (0..<design.colCount).map { c in
                guard r < count, c < self[r].count else { return "none" }
                return self[r][c]
            }
        }
    }
}
