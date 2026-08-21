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
/// build a fresh one whenever the macro list or the capacity changes.
struct MacroBudget: Equatable {
    var capacity: MacroCapacity
    var source: MacroCapacitySource
    var usedBytes: Int
    var usedSlots: Int

    init(capacity: MacroCapacity, source: MacroCapacitySource, macros: [MacroDefinition]) {
        self.capacity = capacity
        self.source = source
        self.usedBytes = macros.reduce(0) { $0 + $1.compiledSize }
        self.usedSlots = macros.count
    }

    var totalBytes: Int { capacity.macroBytes }

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
    /// Also honest about `source == .floor`: those numbers are
    /// `MacroCapacity.floor`, a made-up under-promise, not anything a board
    /// has ever confirmed. `summaryLabel`/`budgetSummary` already say
    /// "(estimated)" for the same reason — this is the one of the three
    /// that actually blocks an action, so it can't afford to read as though
    /// a real board was consulted.
    var blockReason: String? {
        let estimate = source == .floor ? " (estimated)" : ""
        if usedSlots > 0 && (capacity.macroBytes == 0 || capacity.macroSlots == 0) {
            return "This board has no macro memory\(estimate)."
        }
        if usedSlots > capacity.macroSlots {
            return "This board has \(capacity.macroSlots) macro slots\(estimate); \(usedSlots) macros are defined."
        }
        if usedBytes > capacity.macroBytes {
            return "Macros exceed this board's memory by \(usedBytes - capacity.macroBytes) bytes\(estimate)."
        }
        return nil
    }

    var canFlash: Bool { blockReason == nil }

    /// "148 of 384 bytes · slot 3" in the palette column's SLOT section.
    func summaryLabel(slot: Int) -> String {
        let estimate = isEstimate ? " (estimated)" : ""
        return "\(usedBytes) of \(totalBytes) bytes · slot \(slot)\(estimate)"
    }
}
