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

    /// Macros, added by this editor and read by the firmware's macro player.
    ///
    /// Optional rather than defaulted-empty on purpose: a `keymap.json`
    /// written before macros existed must not gain a `"macros": []` key
    /// merely from being opened and saved. `JSONEncoder` omits a nil
    /// optional entirely, so the lossless-save guarantee holds.
    var macros: [MacroDefinition]?

    /// `macros` with nil read as empty, for call sites that only read.
    var macroList: [MacroDefinition] { macros ?? [] }

    /// The lowest unused slot number, so deleting a macro frees its slot for
    /// reuse rather than leaving a permanent hole.
    var nextMacroID: Int {
        let used = Set(macroList.map(\.id))
        var candidate = 0
        while used.contains(candidate) { candidate += 1 }
        return candidate
    }

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

    /// Rewrites every `mo:`/`tg:` cell in every layer so it still names the
    /// same physical layer after the layer at `index` has been removed from
    /// `layers`. Without this, deleting a layer silently breaks every
    /// reference above it: the firmware's `getAction` only walks
    /// `0..<keymaps.count` and `isLayerActive` only reports layers it has,
    /// so an off-by-one `mo:`/`tg:` becomes a permanently dead key.
    ///
    /// - references *below* `index` are untouched,
    /// - references *above* it shift down by one,
    /// - references *to* it become `none` -- the layer they named no longer
    ///   exists, and `none` says that honestly rather than leaving a token
    ///   that can never fire.
    ///
    /// Cells that aren't layer references (including `.raw` tokens this app
    /// doesn't understand) are left byte-for-byte alone, preserving the
    /// lossless-save guarantee above.
    mutating func renumberLayerReferences(afterRemoving index: Int) {
        for layer in layers.indices {
            for row in layers[layer].indices {
                for col in layers[layer][row].indices {
                    guard let rewritten = Self.renumbering(
                        layers[layer][row][col],
                        afterRemoving: index
                    ) else { continue }
                    layers[layer][row][col] = rewritten
                }
            }
        }
    }

    /// The replacement for one cell, or `nil` when it needs no change.
    private static func renumbering(_ cell: String, afterRemoving index: Int) -> String? {
        switch ActionToken.parse(cell) {
        case .momentaryLayer(let n) where n > index:
            return ActionToken.momentaryLayer(n - 1).canonicalString
        case .toggleLayer(let n) where n > index:
            return ActionToken.toggleLayer(n - 1).canonicalString
        case .momentaryLayer(let n), .toggleLayer(let n):
            return n == index ? ActionToken.none.canonicalString : nil
        default:
            return nil
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
