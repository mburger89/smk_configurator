import Testing
@testable import SMKConfigurator

@Suite("Macro capacity degrades and improves with whatever the board reports")
struct MacroCapacityTests {
    /// Builds a macro whose `compiledSize` is exactly `bytes`. Derives the
    /// fixed overhead (macro header + name + the `.text` step's own header)
    /// from an empty-payload macro rather than hardcoding it, so this stays
    /// correct if the bytecode layout's byte counts ever change -- as they
    /// already have once this session (delivery byte added to `.text`).
    private func macro(_ id: Int, bytes: Int) -> MacroDefinition {
        let overhead = MacroDefinition(id: id, name: "n",
                                       steps: [.text("", delivery: .keystrokes, msPerChar: 12)]).compiledSize
        let payload = String(repeating: "x", count: max(0, bytes - overhead))
        return MacroDefinition(id: id, name: "n",
                               steps: [.text(payload, delivery: .keystrokes, msPerChar: 12)])
    }

    @Test("a board's reported capacity is used exactly and is not an estimate")
    func reportedCapacityIsExact() {
        let budget = MacroBudget(capacity: MacroCapacity(macroBytes: 8192, macroSlots: 32),
                                 source: .device, macros: [macro(0, bytes: 100)])
        #expect(budget.usedBytes == 100)
        #expect(budget.totalBytes == 8192)
        #expect(budget.isEstimate == false)
        #expect(budget.canFlash)
    }

    @Test("with no board ever seen, the floor profile applies and is labelled an estimate")
    func floorProfileIsAnEstimate() {
        let budget = MacroBudget(capacity: .floor, source: .floor, macros: [])
        #expect(budget.totalBytes == MacroCapacity.floor.macroBytes)
        #expect(budget.isEstimate)
    }

    @Test("a last-known capacity is exact in value but still flagged as remembered")
    func lastKnownIsRemembered() {
        let budget = MacroBudget(capacity: MacroCapacity(macroBytes: 4096, macroSlots: 16),
                                 source: .lastKnown, macros: [])
        #expect(budget.totalBytes == 4096)
        #expect(budget.isEstimate)
        #expect(budget.canFlash)
    }

    @Test("a board reporting zero macro memory blocks flashing but not editing")
    func zeroCapacityBlocksFlashOnly() {
        let budget = MacroBudget(capacity: MacroCapacity(macroBytes: 0, macroSlots: 0),
                                 source: .device, macros: [macro(0, bytes: 20)])
        #expect(budget.canFlash == false)
        #expect(budget.blockReason == "This board has no macro memory.")
    }

    @Test("a board reporting zero macro memory doesn't block an otherwise macro-free keymap")
    func zeroCapacityWithNoMacrosStillFlashes() {
        // Regression: `blockReason` used to key off `macroBytes == 0` alone,
        // so a small-flash board that legitimately reports zero macro bytes
        // could never receive even an ordinary keymap with no macros in it.
        let budget = MacroBudget(capacity: MacroCapacity(macroBytes: 0, macroSlots: 0),
                                 source: .device, macros: [])
        #expect(budget.canFlash)
        #expect(budget.blockReason == nil)
    }

    @Test("exceeding the byte budget blocks flashing and names the overage")
    func overBudgetBlocksFlash() {
        let budget = MacroBudget(capacity: MacroCapacity(macroBytes: 50, macroSlots: 32),
                                 source: .device, macros: [macro(0, bytes: 80)])
        #expect(budget.usedBytes == 80)
        #expect(budget.canFlash == false)
        #expect(budget.blockReason == "Macros exceed this board's memory by 30 bytes.")
    }

    @Test("exceeding the slot count blocks flashing")
    func overSlotsBlocksFlash() {
        let macros = (0..<3).map { macro($0, bytes: 10) }
        let budget = MacroBudget(capacity: MacroCapacity(macroBytes: 8192, macroSlots: 2),
                                 source: .device, macros: macros)
        #expect(budget.canFlash == false)
        #expect(budget.blockReason == "This board has 2 macro slots; 3 macros are defined.")
    }

    @Test("fill fraction is clamped to 0...1 so the meter can't overflow its track")
    func fillFractionIsClamped() {
        let budget = MacroBudget(capacity: MacroCapacity(macroBytes: 50, macroSlots: 32),
                                 source: .device, macros: [macro(0, bytes: 80)])
        #expect(budget.fillFraction == 1.0)

        let empty = MacroBudget(capacity: MacroCapacity(macroBytes: 0, macroSlots: 0),
                                source: .device, macros: [])
        #expect(empty.fillFraction == 0.0)
    }

    @Test("a budget that can't flash explains why in one sentence")
    func blockReasonIsAFullSentence() {
        let budget = MacroBudget(capacity: MacroCapacity(macroBytes: 0, macroSlots: 0),
                                 source: .device, macros: [macro(0, bytes: 20)])
        let reason = budget.blockReason
        #expect(reason?.hasSuffix(".") == true)
        #expect(reason?.isEmpty == false)
    }

    @Test("blockReason under the never-connected floor says its numbers are estimated")
    func blockReasonUnderFloorIsHonestAboutItsSource() {
        // The floor's numbers are a made-up under-promise, not anything a
        // board reported. `summaryLabel`/`budgetSummary` already say
        // "(estimated)" for exactly this reason; `blockReason` is the one
        // string of the three that actually blocks an action, so it must
        // not read as though a real board was consulted.
        let macros = (0..<(MacroCapacity.floor.macroSlots + 1)).map { macro($0, bytes: 10) }
        let budget = MacroBudget(capacity: .floor, source: .floor, macros: macros)
        #expect(budget.canFlash == false)
        #expect(budget.blockReason?.contains("estimated") == true)
    }

    @Test("blockReason from a real device report says nothing about being estimated")
    func blockReasonFromDeviceIsNotLabelledEstimated() {
        let macros = (0..<3).map { macro($0, bytes: 10) }
        let budget = MacroBudget(capacity: MacroCapacity(macroBytes: 8192, macroSlots: 2),
                                 source: .device, macros: macros)
        #expect(budget.blockReason?.contains("estimated") == false)
    }
}
