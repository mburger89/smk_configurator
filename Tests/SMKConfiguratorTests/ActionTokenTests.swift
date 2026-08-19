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

    /// The real scenario this guards: a keymap.json written by a *newer*
    /// firmware, naming a key this build's vocabulary doesn't have yet, must
    /// survive a load/save round-trip rather than being silently dropped.
    /// (This used to use "key:f13" as its example -- f13 is real vocabulary now,
    /// which is what `f13ParsesNowThatItIsRealVocabulary` below records.)
    @Test("unrecognized cell text is preserved verbatim, never dropped")
    func unknownTokenPreserved() {
        let parsed = ActionToken.parse("key:someFutureKey")
        #expect(parsed == .raw("key:someFutureKey"))
        #expect(parsed.canonicalString == "key:someFutureKey")
    }

    @Test("f13 parses as a real key now that the vocabulary covers it")
    func f13ParsesNowThatItIsRealVocabulary() {
        #expect(ActionToken.parse("key:f13") == .key(.f13))
        #expect(ActionToken.parse("key:insert") == .key(.insert))
        #expect(ActionToken.parse("key:exsel") == .key(.exsel))
    }
}
