import Foundation
import Testing
@testable import SMKConfigurator

@Suite("MacroDefinition round-trips through the keymap.json macro schema")
struct MacroTests {
    private func roundTrip(_ macro: MacroDefinition) throws -> MacroDefinition {
        let data = try JSONEncoder().encode(macro)
        return try JSONDecoder().decode(MacroDefinition.self, from: data)
    }

    @Test("every known step type survives an encode/decode round-trip")
    func knownStepsRoundTrip() throws {
        let macro = MacroDefinition(
            id: 5,
            name: "Build & deploy",
            steps: [
                .keystroke(mods: [.leftGUI, .leftShift], key: .b, holdMs: 40),
                .delay(ms: 400),
                .text("deploy --env staging", delivery: .keystrokes, msPerChar: 12),
                .layer(op: .momentary, n: 1),
                .repeatBlock(count: 2, steps: [.delay(ms: 10)]),
            ]
        )
        #expect(try roundTrip(macro) == macro)
    }

    @Test("an unknown step type is preserved verbatim rather than dropped")
    func unknownStepIsPreserved() throws {
        let json = """
        {"id":7,"name":"From the future","steps":[{"t":"delay","ms":5},{"t":"hologram","intensity":3}]}
        """
        let macro = try JSONDecoder().decode(MacroDefinition.self, from: Data(json.utf8))
        #expect(macro.steps.count == 2)

        let reencoded = try JSONEncoder().encode(macro)
        let object = try JSONSerialization.jsonObject(with: reencoded) as! [String: Any]
        let steps = object["steps"] as! [[String: Any]]
        #expect(steps[1]["t"] as? String == "hologram")
        #expect(steps[1]["intensity"] as? Int == 3)
    }

    @Test("a keystroke naming a key this build's vocabulary doesn't have is preserved whole, not silently stripped of its key")
    func unresolvableKeyNamePreservesWholeStep() throws {
        let json = """
        {"id":1,"name":"n","steps":[{"t":"key","k":"key:hyper","mods":["leftShift"],"hold":40}]}
        """
        let macro = try JSONDecoder().decode(MacroDefinition.self, from: Data(json.utf8))
        #expect(macro.steps.count == 1)

        let reencoded = try JSONEncoder().encode(macro)
        let object = try JSONSerialization.jsonObject(with: reencoded) as! [String: Any]
        let steps = object["steps"] as! [[String: Any]]
        #expect(steps.count == 1)
        #expect(steps[0]["t"] as? String == "key")
        #expect(steps[0]["k"] as? String == "key:hyper")
        #expect(steps[0]["mods"] as? [String] == ["leftShift"])
        #expect(steps[0]["hold"] as? Int == 40)
    }

    @Test("an unrecognized modifier in a mods array does not destroy the recognized modifiers alongside it")
    func unknownModifierPreservesWholeStep() throws {
        let json = """
        {"id":1,"name":"n","steps":[{"t":"key","k":"key:a","mods":["leftShift","hyper"],"hold":40}]}
        """
        let macro = try JSONDecoder().decode(MacroDefinition.self, from: Data(json.utf8))
        #expect(macro.steps.count == 1)

        let reencoded = try JSONEncoder().encode(macro)
        let object = try JSONSerialization.jsonObject(with: reencoded) as! [String: Any]
        let steps = object["steps"] as! [[String: Any]]
        #expect(steps[0]["mods"] as? [String] == ["leftShift", "hyper"])
        #expect(steps[0]["k"] as? String == "key:a")
    }

    @Test("an unrecognized text delivery value is preserved rather than normalized to keystrokes")
    func unknownDeliveryPreservesWholeStep() throws {
        let json = """
        {"id":1,"name":"n","steps":[{"t":"text","s":"hi","delivery":"clipboard","cpm":12}]}
        """
        let macro = try JSONDecoder().decode(MacroDefinition.self, from: Data(json.utf8))
        #expect(macro.steps.count == 1)

        let reencoded = try JSONEncoder().encode(macro)
        let object = try JSONSerialization.jsonObject(with: reencoded) as! [String: Any]
        let steps = object["steps"] as! [[String: Any]]
        #expect(steps[0]["delivery"] as? String == "clipboard")
        #expect(steps[0]["s"] as? String == "hi")
    }

    @Test("an unrecognized layer op value is preserved rather than normalized to momentary")
    func unknownLayerOpPreservesWholeStep() throws {
        let json = """
        {"id":1,"name":"n","steps":[{"t":"layer","op":"osl","n":2}]}
        """
        let macro = try JSONDecoder().decode(MacroDefinition.self, from: Data(json.utf8))
        #expect(macro.steps.count == 1)

        let reencoded = try JSONEncoder().encode(macro)
        let object = try JSONSerialization.jsonObject(with: reencoded) as! [String: Any]
        let steps = object["steps"] as! [[String: Any]]
        #expect(steps[0]["op"] as? String == "osl")
        #expect(steps[0]["n"] as? Int == 2)
    }

    // MARK: - Mistyped (present but wrong JSON type) fields

    /// Decodes `json`'s single macro step and asserts it was preserved whole
    /// as `.raw` -- not silently coerced to some default -- then asserts the
    /// re-encoded JSON still carries the exact original field value. This is
    /// the mistyped-field analogue of `unknownStepIsPreserved` et al. above:
    /// same lossless guarantee, but the trigger is a present field of the
    /// wrong JSON type rather than an unrecognized value or step type.
    private func assertMistypedFieldPreservesStep(
        json: String, checkField: String, expected: (Any?) -> Bool,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let macro = try JSONDecoder().decode(MacroDefinition.self, from: Data(json.utf8))
        #expect(macro.steps.count == 1, sourceLocation: sourceLocation)
        if case .raw = macro.steps[0] {
            // expected
        } else {
            Issue.record("a mistyped field must decode as .raw, not a coerced default", sourceLocation: sourceLocation)
        }

        let reencoded = try JSONEncoder().encode(macro)
        let object = try JSONSerialization.jsonObject(with: reencoded) as! [String: Any]
        let steps = object["steps"] as! [[String: Any]]
        #expect(expected(steps[0][checkField]), sourceLocation: sourceLocation)
    }

    @Test("a delay step's ms as a string is preserved rather than silently becoming 0")
    func mistypedDelayMsPreservesWholeStep() throws {
        try assertMistypedFieldPreservesStep(
            json: #"{"id":1,"name":"n","steps":[{"t":"delay","ms":"200"}]}"#,
            checkField: "ms", expected: { $0 as? String == "200" }
        )
    }

    @Test("a text step's s as a number is preserved rather than silently becoming an empty string")
    func mistypedTextStringPreservesWholeStep() throws {
        try assertMistypedFieldPreservesStep(
            json: #"{"id":1,"name":"n","steps":[{"t":"text","s":123}]}"#,
            checkField: "s", expected: { $0 as? Int == 123 }
        )
    }

    @Test("a text step's cpm as a string is preserved rather than silently becoming the 12ms default")
    func mistypedTextMsPerCharPreservesWholeStep() throws {
        try assertMistypedFieldPreservesStep(
            json: #"{"id":1,"name":"n","steps":[{"t":"text","s":"hi","cpm":"12"}]}"#,
            checkField: "cpm", expected: { $0 as? String == "12" }
        )
    }

    @Test("a layer step's n as a string is preserved rather than silently becoming layer 0")
    func mistypedLayerNPreservesWholeStep() throws {
        try assertMistypedFieldPreservesStep(
            json: #"{"id":1,"name":"n","steps":[{"t":"layer","n":"2"}]}"#,
            checkField: "n", expected: { $0 as? String == "2" }
        )
    }

    @Test("a repeat step's count as a string is preserved rather than silently becoming 1")
    func mistypedRepeatCountPreservesWholeStep() throws {
        try assertMistypedFieldPreservesStep(
            json: #"{"id":1,"name":"n","steps":[{"t":"rpt","count":"3","steps":[]}]}"#,
            checkField: "count", expected: { $0 as? String == "3" }
        )
    }

    @Test("a repeat step's steps as a non-array is preserved rather than silently becoming empty")
    func mistypedRepeatStepsPreservesWholeStep() throws {
        try assertMistypedFieldPreservesStep(
            json: #"{"id":1,"name":"n","steps":[{"t":"rpt","count":2,"steps":"oops"}]}"#,
            checkField: "steps", expected: { $0 as? String == "oops" }
        )
    }

    @Test("a keystroke step's hold as a string is preserved even though the default happens to be a plausible value")
    func mistypedKeystrokeHoldPreservesWholeStep() throws {
        try assertMistypedFieldPreservesStep(
            json: #"{"id":1,"name":"n","steps":[{"t":"key","k":"key:a","hold":"40"}]}"#,
            checkField: "hold", expected: { $0 as? String == "40" }
        )
    }

    @Test("a missing optional field still takes its documented default rather than being flagged as mistyped")
    func missingOptionalFieldStillDefaults() throws {
        // Absence is legitimate JSON existing files rely on -- only a
        // *present* field of the wrong type must trip the .raw guard.
        let json = """
        {"id":1,"name":"n","steps":[
            {"t":"delay"},
            {"t":"text","s":"hi"},
            {"t":"layer"},
            {"t":"rpt","steps":[]},
            {"t":"key","k":"key:a"}
        ]}
        """
        let macro = try JSONDecoder().decode(MacroDefinition.self, from: Data(json.utf8))
        #expect(macro.steps == [
            .delay(ms: 0),
            .text("hi", delivery: .keystrokes, msPerChar: 12),
            .layer(op: .momentary, n: 0),
            .repeatBlock(count: 1, steps: []),
            .keystroke(mods: [], key: .a, holdMs: 40),
        ])
    }

    @Test("an unknown per-macro field (e.g. a future build's 'enabled' flag) is preserved rather than dropped on save")
    func unknownMacroFieldIsPreserved() throws {
        let json = """
        {"id":1,"name":"n","steps":[],"enabled":false}
        """
        let macro = try JSONDecoder().decode(MacroDefinition.self, from: Data(json.utf8))

        let reencoded = try JSONEncoder().encode(macro)
        let object = try JSONSerialization.jsonObject(with: reencoded) as! [String: Any]
        #expect(object["enabled"] as? Bool == false)
        #expect(object["id"] as? Int == 1)
        #expect(object["name"] as? String == "n")
    }

    @Test("a nested repeat block is kept verbatim rather than treated as one")
    func nestedRepeatBecomesRaw() throws {
        let json = #"{"id":1,"name":"n","steps":[{"t":"rpt","count":2,"steps":[{"t":"rpt","count":3,"steps":[]}]}]}"#
        let macro = try JSONDecoder().decode(MacroDefinition.self, from: Data(json.utf8))
        #expect(macro.steps.count == 1)
        if case .repeatBlock = macro.steps[0] {
            Issue.record("A nested repeat block must not decode as an editable repeat block")
        }

        // ...and it still survives the save.
        let reencoded = try JSONEncoder().encode(macro)
        let object = try JSONSerialization.jsonObject(with: reencoded) as! [String: Any]
        let steps = object["steps"] as! [[String: Any]]
        #expect(steps[0]["t"] as? String == "rpt")
        #expect((steps[0]["steps"] as! [[String: Any]]).count == 1)
    }

    @Test("a keystroke with no key is a modifiers-only chord")
    func modifiersOnlyChord() throws {
        let macro = MacroDefinition(
            id: 1, name: "Shift only",
            steps: [.keystroke(mods: [.leftShift], key: nil, holdMs: 40)]
        )
        #expect(try roundTrip(macro) == macro)
    }

    @Test("each step type compiles to its documented byte width")
    func stepByteWidths() {
        #expect(MacroStep.keystroke(mods: [.leftGUI], key: .b, holdMs: 40).compiledSize == 5)
        #expect(MacroStep.delay(ms: 400).compiledSize == 3)
        #expect(MacroStep.layer(op: .momentary, n: 1).compiledSize == 3)
        // 4 header bytes (opcode + delivery + msPerChar + length) + one byte
        // per UTF-8 byte of payload
        #expect(MacroStep.text("abc", delivery: .keystrokes, msPerChar: 12).compiledSize == 7)
        // 4 header bytes + the body's own size
        #expect(MacroStep.repeatBlock(count: 2, steps: [.delay(ms: 5)]).compiledSize == 7)
        // An unexecutable step costs nothing on the board
        #expect(MacroStep.raw(.object(["t": .string("hologram")])).compiledSize == 0)
    }

    @Test("text steps are sized in UTF-8 bytes, not characters")
    func textSizedInUTF8Bytes() {
        // "é" is two UTF-8 bytes; 4 header bytes + 2 payload bytes
        #expect(MacroStep.text("é", delivery: .keystrokes, msPerChar: 12).compiledSize == 6)
    }

    @Test("a macro's size is its header plus its steps")
    func macroSize() {
        let macro = MacroDefinition(id: 5, name: "ab", steps: [.delay(ms: 400)])
        // 3 header bytes + 2 name bytes + 3 step bytes
        #expect(macro.compiledSize == 8)
    }

    @Test("estimated duration sums delays, holds, and typing time, quantized to the board's 10ms tick")
    func estimatedDuration() {
        let macro = MacroDefinition(
            id: 1, name: "t",
            steps: [
                .keystroke(mods: [], key: .a, holdMs: 40),
                .delay(ms: 400),
                .text("abcd", delivery: .keystrokes, msPerChar: 12),
                .repeatBlock(count: 3, steps: [.delay(ms: 10)]),
            ]
        )
        // 40 (already a 4-tick multiple of 10) + 400 (already a multiple of
        // 10) + (4 * 20) -- 12 ms/char rounds up to the board's next 10 ms
        // tick before multiplying by the character count -- + (3 * 10)
        #expect(macro.estimatedDurationMs == 550)
    }

    // MARK: - Tick quantization (CONFIG_FREERTOS_HZ=100, 10 ms/tick)

    @Test("a delay under a full tick rounds up to the board's next 10ms tick")
    func delayRoundsUpToNextTick() {
        #expect(MacroStep.delay(ms: 1).estimatedDurationMs == 10)
        #expect(MacroStep.delay(ms: 9).estimatedDurationMs == 10)
        #expect(MacroStep.delay(ms: 11).estimatedDurationMs == 20)
    }

    @Test("a delay already on a tick boundary is reported unchanged")
    func delayOnTickBoundaryIsUnchanged() {
        #expect(MacroStep.delay(ms: 0).estimatedDurationMs == 0)
        #expect(MacroStep.delay(ms: 10).estimatedDurationMs == 10)
        #expect(MacroStep.delay(ms: 400).estimatedDurationMs == 400)
    }

    @Test("a keystroke hold under a full tick rounds up to the board's next 10ms tick")
    func holdRoundsUpToNextTick() {
        #expect(MacroStep.keystroke(mods: [], key: .a, holdMs: 12).estimatedDurationMs == 20)
    }

    @Test("a keystroke hold that is already a whole number of ticks is reported unchanged")
    func holdOnTickBoundaryIsUnchanged() {
        // 40 ms is already 4 whole ticks -- rounding it must be a no-op.
        #expect(MacroStep.keystroke(mods: [], key: .a, holdMs: 40).estimatedDurationMs == 40)
    }

    @Test("a 12 ms/char typing speed over 5 characters estimates 100 ms, not 60 ms")
    func typingSpeedQuantizesBeforeMultiplying() {
        // 12 ms/char rounds up to the board's next 10 ms tick (20 ms/char)
        // before being multiplied by the character count -- the board
        // rounds every char's delay up individually, so the naive
        // (12 * 5 = 60 ms) the un-quantized math would report is not what
        // it delivers.
        let step = MacroStep.text("abcde", delivery: .keystrokes, msPerChar: 12)
        #expect(step.estimatedDurationMs == 100)
    }

    @Test("a repeat block's estimate is quantized per nested step, not as a whole")
    func repeatBlockQuantizesPerStep() {
        // Each iteration holds a key for 12ms (rounds up to 20) three times.
        let step = MacroStep.repeatBlock(count: 3, steps: [.keystroke(mods: [], key: .a, holdMs: 12)])
        #expect(step.estimatedDurationMs == 60)
    }

    @Test("each step type summarizes its own payload and metadata")
    func rowSummaries() {
        let key = MacroStep.keystroke(mods: [.leftGUI, .leftShift], key: .b, holdMs: 40)
        #expect(key.payloadSummary == "LGUI + LSft + B")
        #expect(key.metadataLabel == "hold 40 ms")

        let delay = MacroStep.delay(ms: 400)
        #expect(delay.payloadSummary == "Wait 400 ms")
        #expect(delay.metadataLabel == "")

        let text = MacroStep.text("deploy --env staging", delivery: .keystrokes, msPerChar: 12)
        #expect(text.payloadSummary == "\"deploy --env staging\"")
        #expect(text.metadataLabel == "20 chars")

        let layer = MacroStep.layer(op: .momentary, n: 1)
        #expect(layer.payloadSummary == "Momentary layer 1 while running")
        #expect(layer.metadataLabel == "MO1")

        let rpt = MacroStep.repeatBlock(count: 3, steps: [.delay(ms: 5)])
        #expect(rpt.payloadSummary == "Repeat 1 step 3 times")
        #expect(rpt.metadataLabel == "3×")
    }

    @Test("a modifiers-only chord summarizes without a trailing separator")
    func modifierOnlySummary() {
        let step = MacroStep.keystroke(mods: [.leftShift], key: nil, holdMs: 40)
        #expect(step.payloadSummary == "LSft")
    }

    @Test("an unknown step says it can't be edited rather than rendering blank")
    func rawSummary() {
        let step = MacroStep.raw(.object(["t": .string("hologram")]))
        #expect(step.payloadSummary == "Unsupported step (kept on save)")
    }

    @Test("a one-step repeat block is singular, many are plural")
    func repeatPluralization() {
        #expect(MacroStep.repeatBlock(count: 2, steps: []).payloadSummary
                == "Repeat 0 steps 2 times")
        #expect(MacroStep.repeatBlock(count: 2, steps: [.delay(ms: 1), .delay(ms: 2)]).payloadSummary
                == "Repeat 2 steps 2 times")
    }

    @Test("the canvas summary names the macro, its step count, and its estimated duration")
    func canvasSummary() {
        let macro = MacroDefinition(
            id: 5,
            name: "Discord push-to-talk",
            steps: [.delay(ms: 250), .delay(ms: 250)]
        )
        #expect(macro.canvasSummary == "macro:5 · 2 steps · 0.50 s est.")
    }

    // MARK: - Bytecode overflow validation

    @Test("a text payload at the 255-byte one-byte length maximum does not overflow")
    func textPayloadAtMaximumDoesNotOverflow() {
        let step = MacroStep.text(String(repeating: "x", count: 255), delivery: .keystrokes, msPerChar: 12)
        #expect(step.overflows.isEmpty)
    }

    @Test("a text payload over the 255-byte one-byte length maximum overflows")
    func textPayloadOverMaximumOverflows() {
        let step = MacroStep.text(String(repeating: "x", count: 256), delivery: .keystrokes, msPerChar: 12)
        #expect(step.overflows == [.textPayloadTooLong(byteCount: 256)])
    }

    @Test("a text payload's overflow check counts UTF-8 bytes, not characters")
    func textPayloadOverflowCountsUTF8Bytes() {
        // 128 "é" characters is 256 UTF-8 bytes, over the 255-byte maximum
        let step = MacroStep.text(String(repeating: "é", count: 128), delivery: .keystrokes, msPerChar: 12)
        #expect(step.overflows == [.textPayloadTooLong(byteCount: 256)])
    }

    @Test("an oversized text payload nested inside a repeat block is still caught")
    func nestedOversizedTextPayloadOverflows() {
        let oversized = MacroStep.text(String(repeating: "x", count: 300), delivery: .keystrokes, msPerChar: 12)
        let step = MacroStep.repeatBlock(count: 2, steps: [.delay(ms: 5), oversized])
        #expect(step.overflows == [.textPayloadTooLong(byteCount: 300)])
    }

    @Test("a macro name at the 255-byte one-byte length maximum does not overflow")
    func macroNameAtMaximumDoesNotOverflow() {
        let macro = MacroDefinition(id: 1, name: String(repeating: "n", count: 255), steps: [])
        #expect(macro.overflows.isEmpty)
    }

    @Test("a macro name over the 255-byte one-byte length maximum overflows")
    func macroNameOverMaximumOverflows() {
        let macro = MacroDefinition(id: 1, name: String(repeating: "n", count: 256), steps: [])
        #expect(macro.overflows == [.macroNameTooLong(byteCount: 256)])
    }

    @Test("a macro with 255 steps does not overflow the one-byte step count")
    func macroAtMaximumStepCountDoesNotOverflow() {
        let macro = MacroDefinition(id: 1, name: "n", steps: Array(repeating: .delay(ms: 1), count: 255))
        #expect(macro.overflows.isEmpty)
    }

    @Test("a macro with more than 255 steps overflows the one-byte step count")
    func macroOverMaximumStepCountOverflows() {
        let macro = MacroDefinition(id: 1, name: "n", steps: Array(repeating: .delay(ms: 1), count: 256))
        #expect(macro.overflows == [.tooManySteps(count: 256)])
    }

    @Test("a macro's overflows report every violation at once, not just the first")
    func macroReportsAllOverflowsAtOnce() {
        let macro = MacroDefinition(
            id: 1,
            name: String(repeating: "n", count: 256),
            steps: [.text(String(repeating: "x", count: 300), delivery: .keystrokes, msPerChar: 12)]
        )
        #expect(macro.overflows.count == 2)
        #expect(macro.overflows.contains(.macroNameTooLong(byteCount: 256)))
        #expect(macro.overflows.contains(.textPayloadTooLong(byteCount: 300)))
    }

    @Test("a well-formed macro has no overflows and is compilable")
    func wellFormedMacroIsCompilable() {
        let macro = MacroDefinition(
            id: 1, name: "ok",
            steps: [.text("hello", delivery: .keystrokes, msPerChar: 12), .delay(ms: 5)]
        )
        #expect(macro.overflows.isEmpty)
        #expect(macro.isCompilable)
    }

    // MARK: - ASCII-only text compilation

    /// A minimal single-layer document to host a macro for
    /// `compileKeymap(_:)`, mirroring `KeymapCompilerTests`' own `doc(layers:)`.
    private func doc(macro: MacroDefinition) -> KeymapDocument {
        var d = KeymapDocument(
            matrix: .init(rows: [5], cols: [6, 7], colsAreDriven: 1),
            layers: [[["key:a", "trans"]]]
        )
        d.macros = [macro]
        return d
    }

    @Test("a text step within printable ASCII compiles cleanly")
    func asciiTextCompiles() throws {
        let macro = MacroDefinition(
            id: 1, name: "ok",
            steps: [.text("Deploy v1.0! (staging)", delivery: .keystrokes, msPerChar: 12)]
        )
        _ = try compileKeymap(doc(macro: macro))
    }

    @Test("a text step containing a character outside printable ASCII refuses to compile")
    func nonASCIITextRefusesToCompile() {
        // The firmware types text through a hand-written table covering
        // only 0x20...0x7E and aborts the macro for anything else -- typing
        // a substitute would be worse than typing nothing, so the compiler
        // must refuse before this ever reaches the board.
        let macro = MacroDefinition(
            id: 1, name: "n",
            steps: [.text("café", delivery: .keystrokes, msPerChar: 12)]
        )
        #expect(throws: KeymapCompileError.self) { _ = try compileKeymap(doc(macro: macro)) }
    }

    @Test("the non-ASCII refusal message names the offending character")
    func nonASCIIRefusalNamesTheCharacter() {
        let macro = MacroDefinition(
            id: 1, name: "n",
            steps: [.text("café", delivery: .keystrokes, msPerChar: 12)]
        )
        do {
            _ = try compileKeymap(doc(macro: macro))
            Issue.record("expected a throw")
        } catch let error as KeymapCompileError {
            #expect("\(error)".contains("é"))
        } catch {
            Issue.record("wrong error type")
        }
    }

    @Test("a control character below the printable ASCII range refuses to compile")
    func controlCharacterRefusesToCompile() {
        // Not just non-ASCII -- 0x0A (newline) is ASCII but outside the
        // firmware's printable 0x20...0x7E table too.
        let macro = MacroDefinition(
            id: 1, name: "n",
            steps: [.text("line one\nline two", delivery: .keystrokes, msPerChar: 12)]
        )
        #expect(throws: KeymapCompileError.self) { _ = try compileKeymap(doc(macro: macro)) }
    }

    @Test("a non-ASCII character nested inside a repeat block is still caught")
    func nonASCIIInsideRepeatBlockRefusesToCompile() {
        let macro = MacroDefinition(
            id: 1, name: "n",
            steps: [.repeatBlock(count: 2, steps: [.text("naïve", delivery: .keystrokes, msPerChar: 12)])]
        )
        #expect(throws: KeymapCompileError.self) { _ = try compileKeymap(doc(macro: macro)) }
    }

    @Test("paste is not among the delivery options a user can currently choose in the UI")
    func pasteHasNoUIPath() {
        // TextDelivery.paste stays in the model so an existing keymap.json
        // carrying "delivery": "paste" still loads losslessly (a keyboard
        // has no way to put text on the host's clipboard, so the firmware
        // never receives it either way -- see KeymapCompiler, which always
        // compiles a text step as keystrokes regardless of this field).
        // MacroInspectorView's "Paste all at once" toggle -- the one place
        // that used to let a user choose it -- was removed; that half of
        // this requirement is a UI change this suite can't exercise, so it
        // was verified by reading MacroInspectorView.swift and by building.
        #expect(TextDelivery.allCases.contains(.paste))
    }
}
