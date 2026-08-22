import Testing
@testable import SMKConfigurator

@Suite("Keymap cells compile to the two-byte form the firmware decodes")
struct KeymapCompilerTests {
    @Test("every representable token round-trips through two bytes")
    func cellsRoundTrip() throws {
        let tokens: [ActionToken] = [
            .none, .transparent, .toggleConnection,
            .key(.a), .key(.z), .key(.f12),
            .modifier(.leftShift), .modifier(.rightGUI),
            .momentaryLayer(0), .momentaryLayer(15),
            .toggleLayer(0), .toggleLayer(15),
            .macro(0), .macro(255),
        ]
        for token in tokens {
            let (tag, param) = try encodeCell(token)
            #expect(decodeCell(tag, param) == token, "round trip failed for \(token)")
        }
    }

    @Test("an unknown token refuses to compile and names itself")
    func unknownTokenRefusesToCompile() {
        // A two-byte cell cannot carry an arbitrary string. The file keeps
        // it (KeymapDocument stores raw strings); the board never pretends
        // to have it.
        #expect(throws: KeymapCompileError.self) {
            _ = try encodeCell(.raw("key:hyper"))
        }
    }

    @Test("the refusal message names the offending token")
    func refusalNamesTheToken() {
        do {
            _ = try encodeCell(.raw("wat:99"))
            Issue.record("expected a throw")
        } catch let error as KeymapCompileError {
            #expect("\(error)".contains("wat:99"))
        } catch {
            Issue.record("wrong error type")
        }
    }

    @Test("a macro slot beyond one byte refuses rather than truncating")
    func oversizedMacroSlotRefuses() {
        // The parameter is one byte. Silently wrapping 256 to 0 would bind
        // the key to a different macro than the user chose.
        #expect(throws: KeymapCompileError.self) {
            _ = try encodeCell(.macro(256))
        }
    }

    @Test("a layer index beyond the firmware ceiling refuses")
    func oversizedLayerIndexRefuses() {
        #expect(throws: KeymapCompileError.self) {
            _ = try encodeCell(.momentaryLayer(16))
        }
    }
}
