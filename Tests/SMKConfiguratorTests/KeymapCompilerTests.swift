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

    private func doc(layers: Int) -> KeymapDocument {
        let layer = [["key:a", "trans"]]
        return KeymapDocument(
            matrix: .init(rows: [5], cols: [6, 7], colsAreDriven: 1),
            layers: Array(repeating: layer, count: layers)
        )
    }

    @Test("the header carries the matrix and the counts")
    func headerLayout() throws {
        let bytes = try compileKeymap(doc(layers: 2))
        #expect(bytes[0] == 1)   // rowCount
        #expect(bytes[1] == 2)   // colCount
        #expect(bytes[2] == 1)   // colsAreDriven
        #expect(bytes[3] == 2)   // layerCount
        #expect(bytes[4] == 0)   // macroCount
        #expect(bytes[6] == 5)   // rows[0]
        #expect(bytes[7] == 6)   // cols[0]
        #expect(bytes[8] == 7)   // cols[1]
    }

    @Test("size is header plus two bytes per cell")
    func payloadSize() throws {
        let bytes = try compileKeymap(doc(layers: 2))
        // 6 header + 1 row + 2 cols + (2 layers * 1 * 2 cells * 2 bytes)
        #expect(bytes.count == 6 + 1 + 2 + 8)
    }

    @Test("sixteen layers of a 5x12 board fit the device limit")
    func sixteenLayersFit() throws {
        // The claim the whole binary format rests on. At 11.9 bytes/cell as
        // JSON this was ~11.1KB and could never be uploaded; the firmware's
        // documented 16-layer ceiling was unreachable at about five.
        let layer = Array(repeating: Array(repeating: "key:a", count: 12), count: 5)
        let d = KeymapDocument(
            matrix: .init(rows: [0, 1, 2, 3, 5],
                          cols: [6, 7, 8, 14, 15, 18, 19, 20, 21, 22, 23, 17],
                          colsAreDriven: 1),
            layers: Array(repeating: layer, count: 16)
        )
        let bytes = try compileKeymap(d)
        #expect(bytes.count == 1943)
        #expect(bytes.count < KeymapUploader.maxPayloadLength)
    }

    @Test("an unknown token anywhere fails the whole compile")
    func unknownTokenFailsTheDocument() {
        var d = doc(layers: 1)
        d.layers[0][0][1] = "key:hyper"
        #expect(throws: KeymapCompileError.self) { _ = try compileKeymap(d) }
    }

    @Test("macros are appended after the layers")
    func macrosFollowLayers() throws {
        var d = doc(layers: 1)
        d.macros = [MacroDefinition(id: 3, name: "hi", steps: [.delay(ms: 10)])]
        let bytes = try compileKeymap(d)
        #expect(bytes[4] == 1)   // macroCount
        #expect(bytes.count > 6 + 1 + 2 + 4)
    }
}
