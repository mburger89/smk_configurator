# Binary Keymap Compiler Implementation Plan (editor side)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Compile `KeymapDocument` — matrix, layers and macros — to the binary payload the firmware now reads, and upload that instead of JSON.

**Architecture:** A pure `KeymapCompiler` turning a document into bytes, with a matching decoder used only by tests. `keymap.json` on disk is unchanged and stays lossless; only the wire and storage formats become binary. The capacity meter finally measures the bytes actually stored.

**Tech Stack:** Swift 6, SwiftCrossUI, Swift Testing.

**Spec:** `~/esp/SMK/docs/superpowers/specs/2026-08-21-binary-keymap-format-design.md`
**Firmware counterpart:** `~/esp/SMK/docs/superpowers/plans/2026-08-21-binary-keymap-format.md`

## Global Constraints

- Build: `swift build --target SMKConfigurator --build-system native`. Never a bare `swift build`.
- Test: `swift test --build-system native`. Baseline is **132 tests in 16 suites**; do not regress it.
- Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`), not XCTest.
- **This half is useless alone.** The firmware reads only binary; this editor sends only JSON until the compiler exists. The two land together or not at all.
- **The byte layout is a cross-repo contract** defined by the spec above and `CLAUDE.md`. Three implementations now exist — this compiler, the firmware's decoder, and `~/esp/SMK/generate_default_keymap.sh`. Task 7 is what keeps them honest.
- **`keymap.json` on disk does not change.** Import, export, and the document model stay JSON with raw cell strings. Only `sendToDevice` changes.
- **No new colour literals** in views; everything through `Chrome` or `KeyboardTheme`.
- **`TapTarget` cannot contain an `if`**, and tap targets cannot nest (`Views/UIStyle.swift:98`, `Views/KeyModeViews.swift`).
- Commit after every task. Do not push.

---

## File Structure

**Create:**
- `Sources/SMKConfigurator/Model/KeymapCompiler.swift` — document → bytes, and the cell tag table
- `Tests/SMKConfiguratorTests/KeymapCompilerTests.swift`
- `Tests/SMKConfiguratorTests/BinaryFormatAgreementTests.swift` — the cross-repo pin

**Modify:**
- `Sources/SMKConfigurator/Model/Macro.swift` — `compiledSize` becomes payload-accurate
- `Sources/SMKConfigurator/Model/EditorState.swift` — send binary; wire `CAPS`
- `Sources/SMKConfigurator/Device/KeymapUploadProtocol.swift` — accept bytes
- `Sources/SMKConfigurator/Device/DeviceTransport.swift` — `CAPS` opcode
- `Sources/SMKConfigurator/Views/MacroInspectorView.swift` — drop Paste, quantize timing
- `Sources/SMKConfigurator/Views/MacroEditorViews.swift` — quantize timing
- `CLAUDE.md`

---

### Task 1: Cell encoding

**Files:**
- Create: `Sources/SMKConfigurator/Model/KeymapCompiler.swift`, `Tests/SMKConfiguratorTests/KeymapCompilerTests.swift`

**Interfaces:**
- Produces: `KeymapCellTag`, `encodeCell(_ token: ActionToken) throws -> (UInt8, UInt8)`, `decodeCell(_:_:) -> ActionToken`, `KeymapCompileError`

- [ ] **Step 1: Write the failing test**

Create `Tests/SMKConfiguratorTests/KeymapCompilerTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --build-system native --filter KeymapCompilerTests`
Expected: compile failure — `cannot find 'encodeCell' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/SMKConfigurator/Model/KeymapCompiler.swift` with the tag table
from the spec — `none` 0, `key` 1, `mod` 2, `mo` 3, `tg` 4, `trans` 5,
`toggle_conn` 6, `macro` 7 — plus `encodeCell`/`decodeCell` and a
`KeymapCompileError` carrying the offending token's text and its position.

`decodeCell` exists for tests, not production: it is what makes the
round-trip assertion meaningful. Say so in its doc comment so nobody wires it
into the app.

Refuse rather than truncate on any parameter that does not fit one byte. A
silently wrapped macro slot binds a key to the wrong macro — the kind of bug
that looks like a hardware fault.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --build-system native --filter KeymapCompilerTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/SMKConfigurator/Model/KeymapCompiler.swift Tests/SMKConfiguratorTests/KeymapCompilerTests.swift
git commit -m "Compile a keymap cell to an action tag and parameter"
```

---

### Task 2: Compile the whole document

**Files:**
- Modify: `Sources/SMKConfigurator/Model/KeymapCompiler.swift`, `Tests/SMKConfiguratorTests/KeymapCompilerTests.swift`

**Interfaces:**
- Consumes: `encodeCell`, `KeymapDocument`
- Produces: `compileKeymap(_ document: KeymapDocument) throws -> [UInt8]`

- [ ] **Step 1: Write the failing test**

Append to the suite:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --build-system native --filter KeymapCompilerTests`
Expected: compile failure — `cannot find 'compileKeymap' in scope`.

- [ ] **Step 3: Write minimal implementation**

Add `compileKeymap` emitting, in order: the 6-byte header
(`rowCount`, `colCount`, `colsAreDriven`, `layerCount`, `macroCount`,
reserved), then `rows[]`, then `cols[]`, then every cell of every layer at a
flat two bytes, then each macro.

Macro entries use the step layout already documented in `CLAUDE.md` —
`MacroStep.compiledSize` describes exactly these bytes, so the emitted length
per step must equal `compiledSize` for that step. Assert that in the
implementation rather than hoping; a mismatch there is what makes the
capacity meter lie.

A `.raw` cell anywhere fails the whole compile, naming the token, its layer,
row and column.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --build-system native`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SMKConfigurator/Model/KeymapCompiler.swift Tests/SMKConfiguratorTests/KeymapCompilerTests.swift
git commit -m "Compile a whole keymap document to the binary payload"
```

---

### Task 3: Upload the binary payload

**Files:**
- Modify: `Sources/SMKConfigurator/Device/KeymapUploadProtocol.swift`, `Sources/SMKConfigurator/Model/EditorState.swift`
- Test: `Tests/SMKConfiguratorTests/KeymapUploadProtocolTests.swift`, `Tests/SMKConfiguratorTests/MacroEditingTests.swift`

**Interfaces:**
- Consumes: `compileKeymap`
- Produces: `KeymapUploader.upload(payload:using:progress:)`, `EditorState.compileForUpload() throws -> [UInt8]`

- [ ] **Step 1: Write the failing test**

`KeymapUploader.chunk(offset:data:)` already takes `ArraySlice<UInt8>`, so
the transport is byte-oriented already — only the entry point converts a
`String`. Add tests that `upload` accepts `[UInt8]` directly and still emits
BEGIN, one CHUNK per 28 bytes, then COMMIT, reusing the existing
`MockTransport`.

Then in `MacroEditingTests`, replace the JSON-payload assertions with:
compiling a document with macros produces bytes whose `macroCount` header
byte is non-zero; a document with an unrecognized token makes `sendToDevice`
set `loadError` naming the token **and never construct a transport**.

**Do not call the real `sendToDevice()` from a test that reaches hardware.**
That mistake shipped once in this repo and flashed a physically connected
board during `swift test`. Every guard in `sendToDevice` returns before
`isSendingToDevice = true` and before the `Task {` — assert on those
observable effects, not on transport behaviour.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --build-system native --filter KeymapUpload`
Expected: failure — `upload` has no `payload:` overload.

- [ ] **Step 3: Write minimal implementation**

Change `KeymapUploader.upload` to take `payload: [UInt8]`. Replace
`EditorState.encodeUploadJSON(layers:macros:)` with `compileForUpload()`
calling `compileKeymap(document)`.

Keep the guard ordering in `sendToDevice` exactly as it is — capacity, then
compile (which can now throw), then payload size, each returning **before**
`isSendingToDevice = true` and the `Task {`. A compile failure sets
`loadError` with the compiler's message, which already names the offending
token and its position.

The payload-size guard's message needs updating: it currently explains that
macros upload as JSON and the meter can read green while the upload is too
big. That is no longer true — say what is true now.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --build-system native`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SMKConfigurator/Device/KeymapUploadProtocol.swift Sources/SMKConfigurator/Model/EditorState.swift Tests/SMKConfiguratorTests/
git commit -m "Upload the compiled binary payload instead of JSON"
```

---

### Task 4: An honest capacity meter

**Files:**
- Modify: `Sources/SMKConfigurator/Model/MacroCapacity.swift`, `Sources/SMKConfigurator/Model/Macro.swift`
- Test: `Tests/SMKConfiguratorTests/MacroCapacityTests.swift`

**Interfaces:**
- Consumes: `compileKeymap`
- Produces: `MacroBudget` measuring real payload bytes

- [ ] **Step 1: Write the failing test**

Append tests asserting that a budget built from a document reports
`usedBytes` equal to the macro region's actual compiled length — the bytes
`compileKeymap` emits for those macros, not an independent estimate.

This is the whole point of the change: the meter measured a format nothing
produced. Pin that it now measures the bytes that get stored.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --build-system native --filter MacroCapacityTests`
Expected: failure — the budget's arithmetic is still independent of the
compiler.

- [ ] **Step 3: Write minimal implementation**

Have `MacroBudget` derive `usedBytes` from the compiler rather than restating
the layout. The existing test helper already derives its overhead from
`compiledSize` for exactly this reason — extend that principle to the
production path so the meter cannot drift from the encoder.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --build-system native`

- [ ] **Step 5: Commit**

```bash
git add Sources/SMKConfigurator/Model/MacroCapacity.swift Sources/SMKConfigurator/Model/Macro.swift Tests/SMKConfiguratorTests/MacroCapacityTests.swift
git commit -m "Measure capacity against the bytes actually uploaded"
```

---

### Task 5: Quantize timing to the board's tick

**Files:**
- Modify: `Sources/SMKConfigurator/Views/MacroInspectorView.swift`, `Sources/SMKConfigurator/Model/Macro.swift`
- Test: `Tests/SMKConfiguratorTests/MacroTests.swift`

- [ ] **Step 1: Write the failing test**

The board's scan loop runs at `CONFIG_FREERTOS_HZ=100`, so 10 ms is its
finest resolution. Add tests that `estimatedDurationMs` reports the duration
the board will actually produce — each delay and hold rounded **up** to a
10 ms multiple, matching the firmware's `(ms + 9) / 10`.

A 12 ms/char typing speed currently estimates 12 ms and delivers 20 ms.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --build-system native --filter MacroTests`

- [ ] **Step 3: Write minimal implementation**

Add the rounding to the duration estimate, and change the inspector's delay,
hold and typing-speed controls to 10 ms steps so the UI cannot express a
value the board will silently change.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --build-system native`

- [ ] **Step 5: Commit**

```bash
git add Sources/SMKConfigurator/Views/MacroInspectorView.swift Sources/SMKConfigurator/Model/Macro.swift Tests/SMKConfiguratorTests/MacroTests.swift
git commit -m "Quantize macro timing to the board's 10ms tick"
```

---

### Task 6: Drop Paste, validate text to printable ASCII

**Files:**
- Modify: `Sources/SMKConfigurator/Views/MacroInspectorView.swift`, `Sources/SMKConfigurator/Model/Macro.swift`, `Sources/SMKConfigurator/Model/KeymapCompiler.swift`
- Test: `Tests/SMKConfiguratorTests/MacroTests.swift`

- [ ] **Step 1: Write the failing test**

Two things:

- A text step containing a byte outside `0x20...0x7E` refuses to compile,
  naming the character. The board's table covers printable ASCII only, and a
  character it cannot type must be refused rather than silently dropped.
- `TextDelivery.paste` no longer appears in any UI-facing list.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --build-system native --filter MacroTests`

- [ ] **Step 3: Write minimal implementation**

Remove the Delivery toggle from the inspector. **Keep the `delivery` byte in
the compiled layout as reserved** — the firmware's decoder expects that
stride, and changing it would churn a contract three implementations share
for no gain.

`TextDelivery` stays in the model so existing `keymap.json` files carrying
`"delivery": "paste"` still load. It simply has no UI and compiles as
`keystrokes`.

Add the ASCII validation to the compiler, alongside the unknown-token
refusal, so everything that cannot reach the board is refused in one place.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --build-system native`

- [ ] **Step 5: Commit**

```bash
git add Sources/SMKConfigurator/Views/MacroInspectorView.swift Sources/SMKConfigurator/Model/Macro.swift Sources/SMKConfigurator/Model/KeymapCompiler.swift Tests/SMKConfiguratorTests/MacroTests.swift
git commit -m "Drop Paste and refuse text the board cannot type"
```

---

### Task 7: The cross-repo format pin

Three implementations of this format now exist. This is the only thing that
keeps them agreeing.

**Files:**
- Create: `Tests/SMKConfiguratorTests/BinaryFormatAgreementTests.swift`

- [ ] **Step 1: Write the failing test**

`KeyVocabularyTests` already reaches into the firmware repo, reading
`~/esp/SMK/keycodes.json` to pin the key vocabulary by HID usage. Use the
same approach against a shared artifact:

`~/esp/SMK/generate_default_keymap.sh` compiles `~/esp/SMK/keymap.json` to
`~/esp/SMK/Sources/SMKCore/DefaultKeymapGenerated.swift`. This test loads the
**same** `keymap.json`, compiles it with `compileKeymap`, and asserts the
bytes match the generated literal.

That is a genuine agreement check: two independent encoders, one input, byte
equality. Skip gracefully with a clear message when the firmware repo is not
present, exactly as `KeyVocabularyTests` does — the suite must stay green for
someone who only checked out this repo.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --build-system native --filter BinaryFormatAgreement`
Expected: fails until the firmware side generates that file. **Until then
this task is blocked on the firmware plan's Task 7** — note it and proceed to
Task 8 rather than weakening the assertion to something that passes.

- [ ] **Step 3: Write minimal implementation**

The test is the deliverable. If it fails on a real disagreement, fix whichever
side the spec says is wrong — do not adjust the expectation to match.

- [ ] **Step 4: Commit**

```bash
git add Tests/SMKConfiguratorTests/BinaryFormatAgreementTests.swift
git commit -m "Pin the binary format against the firmware's generator"
```

---

### Task 8: Wire CAPS, and document

**Files:**
- Modify: `Sources/SMKConfigurator/Device/DeviceTransport.swift`, `Sources/SMKConfigurator/Model/EditorState.swift`, `CLAUDE.md`

- [ ] **Step 1: Write the failing test**

Add a test that a `CAPS` response updates `macroCapacity` and sets
`macroCapacitySource` to `.device` — the source that has never been reachable,
so the meter has always said *(estimated)*.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --build-system native --filter MacroCapacityTests`

- [ ] **Step 3: Write minimal implementation**

Add opcode `0x05` to the transport, parse the little-endian response
(`macroBytes` 2, `macroSlots` 1, `keymapMaxLen` 2), and store it on connect.
Persist it per device so a later disconnected session reports `.lastKnown`
rather than falling back to the floor.

Then update `CLAUDE.md`: the binary payload layout, that the firmware's
`CLAUDE.md` and `generate_default_keymap.sh` carry the same contract, that
`keymap.json` on disk stays JSON and lossless while the wire format does not,
that unknown tokens refuse to compile, and that `firmwareVersionLabel` must
be bumped for the firmware build carrying frame version 2.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --build-system native`

- [ ] **Step 5: Run the app and confirm the meter**

`bash Scripts/run.sh`. With no board connected the meter should still read
*(estimated)*. Create a macro and confirm the byte figure moves in step with
what the compiler emits.

- [ ] **Step 6: Commit**

```bash
git add Sources/SMKConfigurator/Device/DeviceTransport.swift Sources/SMKConfigurator/Model/EditorState.swift CLAUDE.md
git commit -m "Read capacity from the board and document the binary format"
```

---

## Out of scope

- Recording from the board (sub-project 4)
- Conditions, flows and Paste execution — all need the host helper
- The firmware half, which is its own plan in `~/esp/SMK`. Neither half works
  alone: the firmware reads only binary, this editor sends only JSON until
  Task 3 lands. **They merge together.**
