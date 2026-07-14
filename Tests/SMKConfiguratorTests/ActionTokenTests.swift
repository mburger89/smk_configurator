import Testing
@testable import SMKConfigurator

@Suite("ActionToken parses/serializes the exact vocabulary LayerEngine.swift accepts")
struct ActionTokenTests {
    @Test("every KeyName round-trips through key:<name>", arguments: KeyName.allCases)
    func keyRoundTrip(name: KeyName) {
        let token = ActionToken.key(name)
        #expect(token.canonicalString == "key:\(name.rawValue)")
        #expect(ActionToken.parse(token.canonicalString) == token)
    }

    @Test("every ModifierName round-trips through mod:<name>", arguments: ModifierName.allCases)
    func modifierRoundTrip(name: ModifierName) {
        let token = ActionToken.modifier(name)
        #expect(token.canonicalString == "mod:\(name.rawValue)")
        #expect(ActionToken.parse(token.canonicalString) == token)
    }

    @Test("layer actions round-trip for every layer index 0...15", arguments: 0...15)
    func layerActionRoundTrip(layer: Int) {
        let mo = ActionToken.momentaryLayer(layer)
        #expect(mo.canonicalString == "mo:\(layer)")
        #expect(ActionToken.parse(mo.canonicalString) == mo)

        let tg = ActionToken.toggleLayer(layer)
        #expect(tg.canonicalString == "tg:\(layer)")
        #expect(ActionToken.parse(tg.canonicalString) == tg)
    }

    @Test("special tokens round-trip")
    func specialTokens() {
        let cases: [(ActionToken, String)] = [
            (.none, "none"),
            (.transparent, "trans"),
            (.toggleConnection, "toggle_conn"),
        ]
        for (token, raw) in cases {
            #expect(token.canonicalString == raw)
            #expect(ActionToken.parse(raw) == token)
        }
    }

    @Test("unrecognized cell text is preserved verbatim, never dropped")
    func unknownTokenPreserved() {
        let parsed = ActionToken.parse("key:f13")
        #expect(parsed == .raw("key:f13"))
        #expect(parsed.canonicalString == "key:f13")
    }
}
