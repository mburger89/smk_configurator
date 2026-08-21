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
        // 3 header bytes + one byte per UTF-8 byte of payload
        #expect(MacroStep.text("abc", delivery: .keystrokes, msPerChar: 12).compiledSize == 6)
        // 4 header bytes + the body's own size
        #expect(MacroStep.repeatBlock(count: 2, steps: [.delay(ms: 5)]).compiledSize == 7)
        // An unexecutable step costs nothing on the board
        #expect(MacroStep.raw(.object(["t": .string("hologram")])).compiledSize == 0)
    }

    @Test("text steps are sized in UTF-8 bytes, not characters")
    func textSizedInUTF8Bytes() {
        // "é" is two UTF-8 bytes
        #expect(MacroStep.text("é", delivery: .keystrokes, msPerChar: 12).compiledSize == 5)
    }

    @Test("a macro's size is its header plus its steps")
    func macroSize() {
        let macro = MacroDefinition(id: 5, name: "ab", steps: [.delay(ms: 400)])
        // 3 header bytes + 2 name bytes + 3 step bytes
        #expect(macro.compiledSize == 8)
    }

    @Test("estimated duration sums delays, holds, and typing time")
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
        // 40 + 400 + (4 * 12) + (3 * 10)
        #expect(macro.estimatedDurationMs == 518)
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
}
