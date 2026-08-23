import Foundation

/// How much macro storage a board has. Reported by the board rather than
/// hardcoded, because the supported ports range from SAMD21-class parts with
/// almost no spare flash to ESP32-C6 and RP2040 with plenty. See contract C2
/// in `docs/superpowers/specs/2026-08-20-macro-creation-design.md`.
struct MacroCapacity: Codable, Equatable, Hashable {
    var macroBytes: Int
    var macroSlots: Int

    /// The smallest board this editor assumes when it has never spoken to
    /// one. Deliberately conservative: an under-promise is corrected upward
    /// the moment a real board answers, whereas an over-promise lets someone
    /// build a macro that can never be flashed. Superseded by any real
    /// device report.
    static let floor = MacroCapacity(macroBytes: 1024, macroSlots: 8)
}

/// Where the capacity numbers in front of the user came from.
enum MacroCapacitySource: Equatable, Hashable {
    /// A connected board reported them just now.
    case device
    /// Remembered from the last time this board was connected.
    case lastKnown
    /// No board has ever been seen; `MacroCapacity.floor` is in use.
    case floor
}

/// Capacity, current usage, and whether flashing is allowed. Purely derived —
/// build a fresh one whenever the macro list (or the whole document) or the
/// capacity changes.
///
/// Macros have no storage budget of their own: they share one payload
/// budget with the compiled layers (the board's `CAPS` response reports
/// `macroBytes == keymapMaxLen` for exactly this reason — see
/// `MacroCapacity`'s doc comment). `init(capacity:source:document:)` is the
/// initializer that knows this: it measures what the layers already cost
/// and reduces `totalBytes` by that amount, so a document with 16 layers
/// reports far less real macro headroom than one with two. The
/// `macros`-only initializer below can't do that — it has no document to
/// measure a layer cost from — so it leaves `layerBytes` at its default of
/// 0 and `totalBytes` equal to the board's whole `capacity.macroBytes`,
/// exactly as this type behaved before macro/layer sharing existed.
struct MacroBudget: Equatable {
    var capacity: MacroCapacity
    var source: MacroCapacitySource
    var usedBytes: Int
    var usedSlots: Int

    /// Bytes `compileKeymap` spends on everything that isn't a macro — the
    /// 6-byte header, the row/col GPIO arrays, and every layer's cells.
    /// Zero unless measured by `init(capacity:source:document:)`.
    var layerBytes: Int

    /// True when `usedBytes` couldn't be proven by an actual compile (one or
    /// more macros contain something the encoder refuses, e.g. a
    /// `.text` step with a character outside printable ASCII) and fell back
    /// to summing `MacroDefinition.compiledSize` instead — see
    /// `compiledMacroBytes(_:)`. That fallback uses the same per-field byte
    /// widths the encoder is asserted to match on every successful compile,
    /// so it's still a faithful count, just not one proven by a real
    /// compile this time.
    var usedBytesIsEstimated: Bool

    /// True when `layerBytes` couldn't be measured because even the
    /// macro-free document doesn't compile (e.g. a layer cell holds a token
    /// this build has no binary tag for). `layerBytes` is 0 in this case —
    /// not a claim that layers cost nothing, just that the cost is unknown
    /// — and `blockReason` overrides its usual byte-math message with this
    /// instead, since no byte comparison is meaningful when the shared cost
    /// can't be measured.
    var layerCostUnknown: Bool

    init(capacity: MacroCapacity, source: MacroCapacitySource, macros: [MacroDefinition], layerBytes: Int = 0) {
        // Disabled macros are omitted from the payload by `compileKeymap`,
        // so counting them here would report a cost the board never pays --
        // and since macros share one budget with layers, "disable a macro to
        // fit" has to actually free bytes or the feature is theatre.
        let counted = macros.filter(\.enabled)
        self.capacity = capacity
        self.source = source
        self.usedSlots = counted.count
        self.layerBytes = layerBytes
        self.layerCostUnknown = false
        (self.usedBytes, self.usedBytesIsEstimated) = Self.compiledMacroBytes(counted)
    }

    /// Builds a budget straight from the document being edited, so
    /// `totalBytes` reflects what's actually left for macros after layers.
    /// Measures `layerBytes` by compiling `document` with its macros
    /// stripped — the only portion of `compileKeymap`'s output that isn't
    /// macros — rather than restating the header/matrix/layer-cell byte
    /// widths independently, the same principle as `compiledMacroBytes(_:)`
    /// below.
    init(capacity: MacroCapacity, source: MacroCapacitySource, document: KeymapDocument) {
        var withoutMacros = document
        withoutMacros.macros = nil
        if let base = try? compileKeymap(withoutMacros) {
            self.init(capacity: capacity, source: source, macros: document.macroList, layerBytes: base.count)
        } else {
            self.init(capacity: capacity, source: source, macros: document.macroList, layerBytes: 0)
            self.layerCostUnknown = true
        }
    }

    /// Bytes `compileKeymap` emits for `macros`, derived from an actual
    /// compile rather than restating the layout independently — probes with
    /// an otherwise-empty document (no matrix, no layers), so the only
    /// bytes in the result besides the fixed 6-byte header are the macros
    /// themselves. Falls back to summing `MacroDefinition.compiledSize` —
    /// the same arithmetic `KeymapCompiler` asserts its own output matches
    /// on every successful compile — if even that probe throws (e.g. a
    /// `.text` step with a non-ASCII character), so a macro that can't be
    /// flashed still gets an honest byte count instead of a crash or a 0.
    private static func compiledMacroBytes(_ macros: [MacroDefinition]) -> (bytes: Int, estimated: Bool) {
        guard !macros.isEmpty else { return (0, false) }
        let probe = KeymapDocument(matrix: .init(rows: [], cols: [], colsAreDriven: 0),
                                   layers: [], macros: macros)
        if let compiled = try? compileKeymap(probe) {
            return (compiled.count - 6, false)
        }
        return (macros.reduce(0) { $0 + $1.compiledSize }, true)
    }

    /// Bytes theoretically left for macros -- unlike `totalBytes`, not
    /// floored at 0. Goes negative when layers alone already spend more
    /// than the whole shared budget (many layers against the deliberately
    /// conservative `.floor` guess is the common way to get there; see
    /// `MacroCapacity.floor`'s doc comment). `blockReason` and the summary
    /// strings read this one, not `totalBytes`, whenever the arithmetic
    /// needs the true deficit or needs to know layers alone are the
    /// reason -- `totalBytes`'s clamp is right for a meter that can't draw
    /// past its own end, but wrong for a calculation that explains *how
    /// far* over the edge things are.
    var remainingBytes: Int { capacity.macroBytes - layerBytes }

    /// Bytes actually left for macros: the board's whole budget minus
    /// whatever the compiled layers already cost (0 unless this was built
    /// with `init(capacity:source:document:)`), floored at 0 so the meter
    /// and the displayed "of N bytes" figure never draw or read negative.
    var totalBytes: Int { max(0, remainingBytes) }

    /// True when the numbers aren't from a board that's connected right now,
    /// so the UI can label the meter honestly.
    var isEstimate: Bool { source != .device }

    /// 0...1, clamped so an over-budget macro fills the track rather than
    /// drawing past its end.
    var fillFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1.0, max(0.0, Double(usedBytes) / Double(totalBytes)))
    }

    /// Why flashing is unavailable, or nil when it's fine. Never blocks
    /// editing or saving to disk — only the upload.
    ///
    /// Guarded on `usedSlots > 0` throughout: a board that reports zero
    /// macro memory (small-flash parts are allowed to) must still accept an
    /// otherwise macro-free keymap. Blocking on capacity alone, regardless
    /// of whether anything actually needs that capacity, would regress
    /// ordinary flashing the day such a board first reports in.
    ///
    /// Honest about `isEstimate` (a previous version only flagged
    /// `source == .floor` here, while `summaryLabel` already flagged both
    /// `.floor` and `.lastKnown` — this is the one of the three strings
    /// that actually blocks an action, so it can't afford to read as though
    /// a real board was consulted, for either kind of estimate).
    var blockReason: String? {
        let estimate = isEstimate ? " (estimated)" : ""
        if layerCostUnknown {
            return "This keymap doesn't compile, so macro headroom can't be measured\(estimate)."
        }
        if usedSlots > 0 && (capacity.macroBytes == 0 || capacity.macroSlots == 0) {
            return "This board has no macro memory\(estimate)."
        }
        if usedSlots > capacity.macroSlots {
            return "This board has \(capacity.macroSlots) macro slots\(estimate); \(usedSlots) macros are defined."
        }
        if usedBytes > totalBytes {
            // `remainingBytes < 0` means layers alone already spend the
            // whole shared budget -- the generic "exceed by N bytes"
            // phrasing below would either need the unclamped deficit (a
            // confusing number: it counts bytes layers, not macros, are
            // responsible for) or, if computed against `totalBytes`
            // instead, would understate how far over things are. Naming
            // layers as the actual cause is clearer than either.
            if remainingBytes < 0 {
                return "Layers alone already use \(layerBytes) of this board's \(capacity.macroBytes) bytes\(estimate), "
                    + "leaving no room for \(usedSlots) macro\(usedSlots == 1 ? "" : "s"); "
                    + "shrink layers or connect a board with more capacity."
            }
            return "Macros exceed this board's memory by \(usedBytes - remainingBytes) bytes\(estimate)."
        }
        return nil
    }

    var canFlash: Bool { blockReason == nil }

    /// The "how much have I used, how much is left, and why the total
    /// might be less than the board's whole memory" fragment shared by the
    /// library header (`MacroLibraryView.budgetSummary` calls
    /// `headerSummaryLabel`) and the step editor's SLOT line
    /// (`summaryLabel(slot:)`) -- built once here, not duplicated in either
    /// view, so the two can't independently drift and so the one tricky
    /// judgment call (what to say when layers alone already spend the
    /// whole shared budget) is made in exactly one place.
    ///
    /// Ordinarily: "148 of 2142 bytes (1943 of 4085 used by layers)" so the
    /// total never shrinks with no explanation. When `remainingBytes < 0`
    /// (layers alone already exceed the whole budget -- `totalBytes` would
    /// read 0, and "0 of 0 bytes" reads like a crash, not a keymap that
    /// doesn't fit yet), names layers as the reason instead of printing a
    /// zeroed-out total: "layers alone use 1943 of 1024 bytes -- no room
    /// left for macros".
    private var byteFragment: String {
        guard remainingBytes >= 0 else {
            return "layers alone use \(layerBytes) of \(capacity.macroBytes) bytes -- no room left for macros"
        }
        let usageNote = usedBytesIsEstimated ? " (macro estimate)" : ""
        let layerNote = layerBytes > 0 ? " (\(layerBytes) of \(capacity.macroBytes) bytes used by layers)" : ""
        return "\(usedBytes) of \(totalBytes) bytes\(usageNote)\(layerNote)"
    }

    /// "148 of 384 bytes · slot 3 (estimated)" in the palette column's SLOT
    /// section -- see `byteFragment` for what replaces the byte portion
    /// once layers are sharing (or have exhausted) the budget.
    func summaryLabel(slot: Int) -> String {
        let estimate = isEstimate ? " (estimated)" : ""
        return "\(byteFragment) · slot \(slot)\(estimate)"
    }

    /// "148 of 2142 bytes (1943 of 4085 used by layers) · 3 of 8 slots
    /// (estimated)" in the macro library header -- the whole-set
    /// counterpart to `summaryLabel(slot:)`, sharing the same
    /// `byteFragment` so the header and the step editor never disagree
    /// about what the numbers mean.
    var headerSummaryLabel: String {
        let estimate = isEstimate ? " (estimated)" : ""
        return "\(byteFragment) · \(usedSlots) of \(capacity.macroSlots) slots\(estimate)"
    }
}
