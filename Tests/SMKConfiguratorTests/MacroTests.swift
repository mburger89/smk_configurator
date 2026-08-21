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
}
