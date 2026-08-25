import Foundation
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

    // MARK: - Measuring against the real compiler, not a restated formula

    /// A 5x12 document with `layerCount` identical layers of "key:a" cells,
    /// the same board shape Task 2's report pinned at 1943 compiled bytes
    /// for 16 layers -- so the numbers here are cross-checkable against that
    /// independently-derived figure, not just internally consistent.
    private func document(layerCount: Int, macros: [MacroDefinition] = []) -> KeymapDocument {
        let matrix = KeymapDocument.Matrix(rows: Array(0..<5), cols: Array(0..<12), colsAreDriven: 1)
        let layer = (0..<5).map { _ in (0..<12).map { _ in "key:a" } }
        return KeymapDocument(matrix: matrix, layers: Array(repeating: layer, count: layerCount), macros: macros)
    }

    @Test("usedBytes equals exactly the macro-region bytes compileKeymap emits for a real document, not compiledSize summed independently")
    func usedBytesMatchesWhatTheCompilerActuallyEmits() throws {
        let macros = [macro(0, bytes: 40), macro(1, bytes: 60)]
        let doc = document(layerCount: 2, macros: macros)

        // The reference: compile the whole document, then compile it again
        // with macros stripped, and take the difference. That difference is
        // -- by construction -- exactly the bytes the macro region costs on
        // the wire, derived the same way `MacroBudget` must derive it.
        let full = try compileKeymap(doc)
        var withoutMacros = doc
        withoutMacros.macros = nil
        let base = try compileKeymap(withoutMacros)
        let expectedMacroBytes = full.count - base.count

        let budget = MacroBudget(capacity: MacroCapacity(macroBytes: 8192, macroSlots: 32),
                                 source: .device, document: doc)
        #expect(budget.usedBytes == expectedMacroBytes)
        #expect(budget.layerBytes == base.count)
    }

    @Test("macro headroom shrinks as layer count grows, because layers and macros share one payload budget")
    func headroomAccountsForLayerCost() {
        let capacity = MacroCapacity(macroBytes: 4085, macroSlots: 32)
        let twoLayers = MacroBudget(capacity: capacity, source: .device, document: document(layerCount: 2))
        let sixteenLayers = MacroBudget(capacity: capacity, source: .device, document: document(layerCount: 16))

        // Cross-checked against Task 2's independently-reported figure: 16
        // layers of this exact 5x12 shape compile to 1943 bytes.
        #expect(sixteenLayers.layerBytes == 1943)
        #expect(twoLayers.layerBytes < sixteenLayers.layerBytes)
        #expect(twoLayers.totalBytes > sixteenLayers.totalBytes)
        #expect(sixteenLayers.totalBytes == capacity.macroBytes - sixteenLayers.layerBytes)
        #expect(twoLayers.totalBytes == capacity.macroBytes - twoLayers.layerBytes)
    }

    @Test("a macro that refuses to compile still reports a byte count instead of crashing or reading zero")
    func uncompilableMacroFallsBackToAHonestEstimate() {
        // A non-ASCII `.text` character makes KeymapCompileError.unsupportedCharacter
        // throw when this macro is actually compiled (see KeymapCompiler's
        // firstUnsupportedCharacter). The budget must not propagate that
        // throw, crash, or silently report 0 -- it falls back to
        // MacroDefinition.compiledSize, the same arithmetic a successful
        // compile is asserted to match.
        let uncompilable = MacroDefinition(id: 0, name: "n",
                                           steps: [.text("café", delivery: .keystrokes, msPerChar: 12)])
        let budget = MacroBudget(capacity: MacroCapacity(macroBytes: 1024, macroSlots: 8),
                                 source: .device, macros: [uncompilable])
        #expect(budget.usedBytes == uncompilable.compiledSize)
        #expect(budget.usedBytesIsEstimated == true)
        #expect(budget.usedBytes > 0)
    }

    @Test("headerSummaryLabel and summaryLabel explain why the total is less than the board's whole memory once layers are sharing it")
    func summaryStringsExplainTheSharedBudget() {
        let capacity = MacroCapacity(macroBytes: 4085, macroSlots: 32)
        let budget = MacroBudget(capacity: capacity, source: .device, document: document(layerCount: 16))

        // Cross-checked against `headroomAccountsForLayerCost`: 16 layers of
        // this shape cost 1943 bytes, leaving 2142 of the 4085-byte budget.
        #expect(budget.layerBytes == 1943)
        #expect(budget.totalBytes == 2142)
        #expect(budget.headerSummaryLabel == "0 of 2142 bytes (1943 of 4085 bytes used by layers) · 0 of 32 slots")
        #expect(budget.summaryLabel(slot: 5) == "0 of 2142 bytes (1943 of 4085 bytes used by layers) · slot 5")
    }

    @Test("when layers alone already exceed the whole shared budget, the summary names layers instead of printing a zeroed-out total")
    func summaryStringsNameLayersWhenTheyAloneExceedTheBudget() {
        // The floor's 1024-byte profile is smaller than 16 layers of this
        // 5x12 shape (1943 bytes) -- the scenario a real board with little
        // flash, or the never-connected floor guess, can land in. Without
        // this branch, `totalBytes` clamps to 0 and the summary would read
        // "0 of 0 bytes", which looks like the app lost its mind rather
        // than a keymap that simply doesn't fit yet.
        let budget = MacroBudget(capacity: .floor, source: .floor, document: document(layerCount: 16))

        #expect(budget.layerBytes == 1943)
        #expect(budget.remainingBytes == 1024 - 1943)
        #expect(budget.totalBytes == 0)
        #expect(budget.headerSummaryLabel
            == "layers alone use 1943 of 1024 bytes -- no room left for macros · 0 of 8 slots (estimated)")
        #expect(budget.summaryLabel(slot: 0)
            == "layers alone use 1943 of 1024 bytes -- no room left for macros · slot 0 (estimated)")
        // Zero macros on an over-budget-by-layers-alone keymap must still
        // flash-gate as before (see `zeroCapacityWithNoMacrosStillFlashes`'s
        // reasoning): the floor is a conservative guess, and the real
        // per-payload guard (`EditorState.sendToDevice`'s step 5) is what
        // actually protects a real board -- blocking here on the guess
        // alone would regress an ordinary macro-free keymap the moment a
        // small board first reports in.
        #expect(budget.canFlash == true)
    }

    @Test("blockReason names layers, not a misleadingly small deficit, when layers alone exceed the budget and macros are on top")
    func blockReasonNamesLayersWhenTheyAloneExceedTheBudget() {
        let macros = [macro(0, bytes: 50)]
        let budget = MacroBudget(capacity: .floor, source: .floor,
                                 document: document(layerCount: 16, macros: macros))

        #expect(budget.usedBytes == 50)
        #expect(budget.canFlash == false)
        #expect(budget.blockReason
            == "Layers alone already use 1943 of this board's 1024 bytes (estimated), "
            + "leaving no room for 1 macro; shrink layers or connect a board with more capacity.")
    }

    @Test("a document whose layers don't compile reports layer cost as unknown rather than silently zero")
    func uncompilableDocumentReportsLayerCostAsUnknown() {
        let matrix = KeymapDocument.Matrix(rows: [0], cols: [0], colsAreDriven: 1)
        // "bogus:token" parses to ActionToken.raw -- a token this build has
        // no binary tag for -- so compileKeymap refuses the whole document,
        // not just the macro region.
        let doc = KeymapDocument(matrix: matrix, layers: [[["bogus:token"]]],
                                 macros: [macro(0, bytes: 10)])

        let budget = MacroBudget(capacity: MacroCapacity(macroBytes: 1024, macroSlots: 8),
                                 source: .device, document: doc)
        #expect(budget.layerCostUnknown == true)
        #expect(budget.layerBytes == 0)
        #expect(budget.canFlash == false)
        #expect(budget.blockReason?.contains("compile") == true)
    }

    @Test("a disabled macro spends no slots and no bytes")
    func disabledMacroIsFree() {
        let steps: [MacroStep] = [.text("hello", delivery: .keystrokes, msPerChar: 10)]
        let enabled = MacroDefinition(id: 0, name: "A", steps: steps)
        var disabled = MacroDefinition(id: 1, name: "B", steps: steps)
        disabled.enabled = false

        let both = MacroBudget(capacity: .floor, source: .device, macros: [enabled, disabled])
        let one = MacroBudget(capacity: .floor, source: .device, macros: [enabled])

        #expect(both.usedSlots == 1)
        #expect(both.usedBytes == one.usedBytes)
    }
}

/// The `.device` source in `MacroCapacitySource` has never been reachable
/// before -- there was no way to ask a board anything. These tests exercise
/// the new `CAPS` opcode (0x05) wiring: decoding the wire response, adopting
/// it on `EditorState`, and persisting it so a later disconnected session
/// reports `.lastKnown` instead of dropping back to `MacroCapacity.floor`.
///
/// None of these ever construct a real `USBRawHIDTransport`/`BLETransport`
/// -- `queryCapacity` is tested against `KeymapUploaderTests.MockTransport`
/// (a fake, see `KeymapUploadProtocolTests.swift`), and `applyDeviceCapacity`
/// takes an already-decoded `DeviceCapacityReport`, never a transport. The
/// only code path that opens a real transport is `EditorState.sendToDevice()`,
/// which none of these tests call -- the same rule the rest of this device
/// layer's tests already follow.
@Suite("CAPS opcode: a board's real capacity reaches the meter")
struct MacroCapacityWireTests {
    /// A well-formed 32-byte CAPS response: byte 0 status (0x00 ok), byte 1
    /// opcode echo, bytes 2-3 macroBytes (u16 LE), byte 4 macroSlots (u8),
    /// bytes 5-6 keymapMaxLen (u16 LE).
    private func capsResponse(macroBytes: UInt16, macroSlots: UInt8, keymapMaxLen: UInt16) -> [UInt8] {
        var response = [UInt8](repeating: 0, count: 32)
        response[0] = 0x00
        response[1] = 0x05
        response[2] = UInt8(macroBytes & 0xFF)
        response[3] = UInt8((macroBytes >> 8) & 0xFF)
        response[4] = macroSlots
        response[5] = UInt8(keymapMaxLen & 0xFF)
        response[6] = UInt8((keymapMaxLen >> 8) & 0xFF)
        return response
    }

    /// A throwaway `UserDefaults(suiteName:)`, exactly `JSONFileStoreTests`'s
    /// pattern, so persistence assertions never touch the real user's
    /// `UserDefaults.standard`.
    private func freshDefaults(_ suite: String = #function) -> UserDefaults {
        let name = "MacroCapacityWireTests.\(suite).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("queryCapacity sends opcode 0x05 and decodes the little-endian response")
    func queryCapacityDecodesResponse() async throws {
        let transport = KeymapUploaderTests.MockTransport(
            responses: [capsResponse(macroBytes: 4000, macroSlots: 255, keymapMaxLen: 4000)]
        )
        let report = try await KeymapUploader.queryCapacity(using: transport)

        #expect(transport.sent.count == 1)
        #expect(transport.sent[0][0] == 0x05)
        #expect(report.macroBytes == 4000)
        #expect(report.macroSlots == 255)
        #expect(report.keymapMaxLen == 4000)
    }

    @Test("queryCapacity decodes a two-byte field spanning both bytes, not just the low byte")
    func queryCapacityDecodesMultiByteField() async throws {
        // 0x0FA0 = 4000: exercises the high byte of the u16 LE fields, so a
        // decoder that dropped the second byte wouldn't be caught by a
        // round value alone.
        let transport = KeymapUploaderTests.MockTransport(
            responses: [capsResponse(macroBytes: 0x0FA0, macroSlots: 32, keymapMaxLen: 0x1234)]
        )
        let report = try await KeymapUploader.queryCapacity(using: transport)
        #expect(report.macroBytes == 0x0FA0)
        #expect(report.keymapMaxLen == 0x1234)
    }

    @Test("queryCapacity throws .nak when the board reports an error status")
    func queryCapacityThrowsOnErrorStatus() async {
        let transport = KeymapUploaderTests.MockTransport(responses: [[0x01, 0x05]])
        await #expect(throws: DeviceTransportError.nak) {
            _ = try await KeymapUploader.queryCapacity(using: transport)
        }
    }

    @MainActor
    @Test("applying a device capacity report switches the meter to .device with the board's numbers")
    func applyingReportSwitchesSourceToDevice() {
        let editor = EditorState(userDefaults: freshDefaults())
        let report = DeviceCapacityReport(macroBytes: 6000, macroSlots: 40, keymapMaxLen: 6000)

        editor.applyDeviceCapacity(report, deviceKey: "usb")

        #expect(editor.macroCapacity == MacroCapacity(macroBytes: 6000, macroSlots: 40))
        #expect(editor.macroCapacitySource == .device)
    }

    @MainActor
    @Test("a device capacity persists so a later session reports .lastKnown, not the floor")
    func persistedCapacityIsLastKnownNextSession() {
        let defaults = freshDefaults()
        let report = DeviceCapacityReport(macroBytes: 5000, macroSlots: 20, keymapMaxLen: 5000)

        let firstSession = EditorState(userDefaults: defaults)
        firstSession.applyDeviceCapacity(report, deviceKey: "usb")

        // A fresh EditorState, sharing only the persisted defaults, models
        // "same board, later launch, nothing plugged in right now."
        let laterSession = EditorState(userDefaults: defaults)

        #expect(laterSession.macroCapacity == MacroCapacity(macroBytes: 5000, macroSlots: 20))
        #expect(laterSession.macroCapacitySource == .lastKnown)
    }

    @MainActor
    @Test("with nothing ever persisted, a fresh session still reports the floor")
    func noPersistedCapacityStillFloors() {
        let editor = EditorState(userDefaults: freshDefaults())
        #expect(editor.macroCapacity == .floor)
        #expect(editor.macroCapacitySource == .floor)
    }
}
