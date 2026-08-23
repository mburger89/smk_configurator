# Macro Creation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a macros rail destination to the configurator where a user builds a macro as an ordered list of steps, saves it, and then places it on a key like any other token.

**Architecture:** Macros are a new optional top-level array in `KeymapDocument`, carried inside `keymap.json` and uploaded through the existing device path. A new `ActionToken.macro(Int)` binds a macro to a key. The macros rail mode has two sub-states — a full-body library table and a four-pane step editor. Macro execution happens on the board; nothing in this plan runs a macro.

**Tech Stack:** Swift 6, SwiftCrossUI, Swift Testing (`import Testing`, `@Suite`/`@Test`/`#expect`).

**Spec:** `docs/superpowers/specs/2026-08-20-macro-creation-design.md`

## Global Constraints

- Build with `swift build --target SMKConfigurator --build-system native`. Never a bare `swift build` — it compiles swift-cross-ui's Windows-only backend and fails.
- Test with `swift test --build-system native --filter <SuiteName>`. Run the full suite with `swift test --build-system native`.
- Run the real app with `bash Scripts/run.sh`.
- **No new colour literals in views.** Every colour comes from `Chrome` in `Views/UIStyle.swift`. Badge colours reuse the keycap palette already in the keymap view: white `#FFFFFF`, modifier yellow `#F7DA71`, layer orange `#F3A75C`, text grey `#C9C9C9`.
- **`TapTarget` cannot contain an `if`.** Its `ZStack` must have exactly two direct children (shape, label), neither from a conditional. Express selected states as *values* passed in, never as branches. See the comment at `Sources/SMKConfigurator/Views/UIStyle.swift:98`.
- **SwiftCrossUI has no drag support and no keyboard shortcuts.** The available gesture modifiers are `onTapGesture`, `onHover`, `onChange`, `onSubmit`, `onOpenURL`. Do not write drag-to-reorder, drop targets, or `⌘`/`⌫` handlers.
- **Exact UI copy** (differs from the HTML reference on purpose — the reference describes gestures this toolkit lacks):
  - `"Select a step to reorder or delete"` (NOT "Drag to reorder · ⌫ to delete")
  - `"Add a step"` (NOT "Drop a step type here, or press ⌘⏎ to append")
  - The primary editor button reads `"Save"` (NOT "Save & flash")
- **`repeatBlock` does not nest.** A repeat block's steps may not contain another repeat block.
- Commit after every task. Do not push.

---

## File Structure

**Create:**
- `Sources/SMKConfigurator/Model/Macro.swift` — `JSONValue`, `MacroStep`, `MacroDefinition`, compiled-size rules
- `Sources/SMKConfigurator/Model/MacroCapacity.swift` — capacity profile and the five meter states
- `Sources/SMKConfigurator/Views/MacroLibraryView.swift` — the full-body library table
- `Sources/SMKConfigurator/Views/MacroEditorViews.swift` — step palette column and canvas header
- `Sources/SMKConfigurator/Views/MacroStepRowView.swift` — one sequence row
- `Sources/SMKConfigurator/Views/MacroInspectorView.swift` — Step / Macro / Timing tabs
- `Tests/SMKConfiguratorTests/MacroTests.swift`
- `Tests/SMKConfiguratorTests/MacroCapacityTests.swift`
- `Tests/SMKConfiguratorTests/MacroEditingTests.swift`

**Modify:**
- `Sources/SMKConfigurator/Model/ActionToken.swift` — add `.macro(Int)`
- `Sources/SMKConfigurator/Model/KeymapDocument.swift` — add optional `macros`
- `Sources/SMKConfigurator/Model/EditorState.swift` — `RailMode.macros`, `MacroWorkspace`, macro editing methods, upload payload
- `Sources/SMKConfigurator/Views/AppIcon.swift` — `.macros` case
- `Sources/SMKConfigurator/Views/IconRailView.swift` — macros rail button
- `Sources/SMKConfigurator/Views/ContentView.swift` — `.macros` cases in the three column properties
- `Sources/SMKConfigurator/Views/PaletteDrawerView.swift` — MACROS section
- `Sources/SMKConfigurator/Views/KeyCapView.swift` — macro name resolver
- `Scripts/generate-icons.sh` — render the macros glyph
- `Tests/SMKConfiguratorTests/ActionTokenTests.swift`, `KeymapDocumentTests.swift`

---

### Task 1: Macro step model with lossless JSON round-trip

The model must survive a step type it does not understand. `KeymapDocument` keeps
cells as raw strings for exactly this reason; macros need the same guarantee via a
`.raw` case holding arbitrary JSON.

**Files:**
- Create: `Sources/SMKConfigurator/Model/Macro.swift`
- Test: `Tests/SMKConfiguratorTests/MacroTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `JSONValue`, `MacroStep`, `MacroDefinition`, `TextDelivery`, `LayerOp`

- [ ] **Step 1: Write the failing test**

Create `Tests/SMKConfiguratorTests/MacroTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --build-system native --filter MacroTests`
Expected: compile failure — `cannot find 'MacroDefinition' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/SMKConfigurator/Model/Macro.swift`:

```swift
import Foundation

/// Arbitrary JSON, used to carry a macro step this build doesn't understand
/// through a load/save cycle unchanged. Same lossless principle as
/// `KeymapDocument`'s raw cell strings and `ActionToken.raw`.
enum JSONValue: Codable, Equatable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unrepresentable JSON")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v):
            // Whole numbers encode as integers so a round-tripped "ms": 400
            // doesn't become 400.0 in the file the firmware parses.
            if v == v.rounded(), abs(v) < 9_007_199_254_740_992 { try c.encode(Int(v)) }
            else { try c.encode(v) }
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}

/// How a `.text` step reaches the host.
enum TextDelivery: String, Codable, Equatable, Hashable, CaseIterable {
    case keystrokes, paste
}

/// The layer action a `.layer` step performs, mirroring the `mo:`/`tg:`
/// tokens `ActionToken` already understands.
enum LayerOp: String, Codable, Equatable, Hashable, CaseIterable {
    case momentary = "mo"
    case toggle = "tg"
}

/// One step of a macro. Mirrors the `steps` schema in
/// `docs/superpowers/specs/2026-08-20-macro-creation-design.md` (C1).
///
/// `.raw` carries a step type this build doesn't know. It is preserved on
/// save and never executed, so a macro authored by a newer build survives
/// an older build opening and saving the file.
enum MacroStep: Codable, Equatable, Hashable, Identifiable {
    case keystroke(mods: [ModifierName], key: KeyName?, holdMs: Int)
    case text(String, delivery: TextDelivery, msPerChar: Int)
    case delay(ms: Int)
    case layer(op: LayerOp, n: Int)
    case repeatBlock(count: Int, steps: [MacroStep])
    case raw(JSONValue)

    var id: String { typeCode + String(describing: self).hashValue.description }

    /// The three-letter badge shown in the palette and on sequence rows.
    var typeCode: String {
        switch self {
        case .keystroke: return "KEY"
        case .text: return "TXT"
        case .delay: return "DLY"
        case .layer: return "LYR"
        case .repeatBlock: return "RPT"
        case .raw: return "???"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case t, k, mods, hold, s, cpm, delivery, ms, op, n, count, steps
    }

    init(from decoder: Decoder) throws {
        // A step whose "t" is missing or unrecognized is kept verbatim.
        guard let c = try? decoder.container(keyedBy: CodingKeys.self),
              let t = try? c.decode(String.self, forKey: .t)
        else {
            self = .raw(try JSONValue(from: decoder))
            return
        }
        switch t {
        case "key":
            let mods = (try? c.decode([ModifierName].self, forKey: .mods)) ?? []
            let keyString = try? c.decode(String.self, forKey: .k)
            let key = keyString.flatMap { s -> KeyName? in
                guard s.hasPrefix("key:") else { return nil }
                return KeyName(rawValue: String(s.dropFirst(4)))
            }
            self = .keystroke(mods: mods, key: key,
                              holdMs: (try? c.decode(Int.self, forKey: .hold)) ?? 40)
        case "text":
            self = .text((try? c.decode(String.self, forKey: .s)) ?? "",
                         delivery: (try? c.decode(TextDelivery.self, forKey: .delivery)) ?? .keystrokes,
                         msPerChar: (try? c.decode(Int.self, forKey: .cpm)) ?? 12)
        case "delay":
            self = .delay(ms: (try? c.decode(Int.self, forKey: .ms)) ?? 0)
        case "layer":
            self = .layer(op: (try? c.decode(LayerOp.self, forKey: .op)) ?? .momentary,
                          n: (try? c.decode(Int.self, forKey: .n)) ?? 0)
        case "rpt":
            let inner = (try? c.decode([MacroStep].self, forKey: .steps)) ?? []
            // Repeat blocks don't nest — the firmware's player uses a single
            // loop counter, not a stack. A nested block written by some other
            // tool is kept verbatim so saving can't destroy it, but it is
            // never executed or edited as a repeat block.
            let nests = inner.contains { if case .repeatBlock = $0 { return true } else { return false } }
            if nests {
                self = .raw(try JSONValue(from: decoder))
            } else {
                self = .repeatBlock(count: (try? c.decode(Int.self, forKey: .count)) ?? 1, steps: inner)
            }
        default:
            self = .raw(try JSONValue(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        if case .raw(let value) = self {
            try value.encode(to: encoder)
            return
        }
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .keystroke(let mods, let key, let holdMs):
            try c.encode("key", forKey: .t)
            if let key { try c.encode("key:\(key.rawValue)", forKey: .k) }
            try c.encode(mods, forKey: .mods)
            try c.encode(holdMs, forKey: .hold)
        case .text(let s, let delivery, let msPerChar):
            try c.encode("text", forKey: .t)
            try c.encode(s, forKey: .s)
            try c.encode(delivery, forKey: .delivery)
            try c.encode(msPerChar, forKey: .cpm)
        case .delay(let ms):
            try c.encode("delay", forKey: .t)
            try c.encode(ms, forKey: .ms)
        case .layer(let op, let n):
            try c.encode("layer", forKey: .t)
            try c.encode(op, forKey: .op)
            try c.encode(n, forKey: .n)
        case .repeatBlock(let count, let steps):
            try c.encode("rpt", forKey: .t)
            try c.encode(count, forKey: .count)
            try c.encode(steps, forKey: .steps)
        case .raw:
            break // handled above
        }
    }
}

/// One macro. `id` is the slot the firmware stores it in and the number the
/// `macro:<id>` action token names.
struct MacroDefinition: Codable, Equatable, Hashable, Identifiable {
    var id: Int
    var name: String
    var steps: [MacroStep]

    init(id: Int, name: String, steps: [MacroStep]) {
        self.id = id
        self.name = name
        self.steps = steps
    }
}
```

Add `Codable` conformance to `ModifierName` by changing its declaration in
`Sources/SMKConfigurator/Model/ActionToken.swift` from
`enum ModifierName: String, CaseIterable, Hashable {` to
`enum ModifierName: String, CaseIterable, Hashable, Codable {`.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --build-system native --filter MacroTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/SMKConfigurator/Model/Macro.swift Sources/SMKConfigurator/Model/ActionToken.swift Tests/SMKConfiguratorTests/MacroTests.swift
git commit -m "Add a lossless macro step model"
```

---

### Task 2: Compiled byte size

The spec (C3) requires the byte meter to be computed from the same rules the
firmware will use, not invented. This task defines those rules; sub-project 3
must match them, and a comment in the code says so.

**Files:**
- Modify: `Sources/SMKConfigurator/Model/Macro.swift`
- Test: `Tests/SMKConfiguratorTests/MacroTests.swift`

**Interfaces:**
- Consumes: `MacroStep`, `MacroDefinition` from Task 1
- Produces: `MacroStep.compiledSize: Int`, `MacroDefinition.compiledSize: Int`, `MacroDefinition.estimatedDurationMs: Int`

- [ ] **Step 1: Write the failing test**

Append to `Tests/SMKConfiguratorTests/MacroTests.swift`, inside the `MacroTests` suite:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --build-system native --filter MacroTests`
Expected: compile failure — `value of type 'MacroStep' has no member 'compiledSize'`.

- [ ] **Step 3: Write minimal implementation**

Append to `Sources/SMKConfigurator/Model/Macro.swift`:

```swift
// MARK: - Compiled size

/// The on-board bytecode layout. These widths are the contract between this
/// editor's byte meter and the firmware's macro player; changing one without
/// the other makes the meter lie. See contract C3 in
/// `docs/superpowers/specs/2026-08-20-macro-creation-design.md`.
///
///   keystroke   opcode(1) + mods(1) + keycode(1) + holdMs(2)      = 5
///   delay       opcode(1) + ms(2)                                 = 3
///   layer       opcode(1) + op(1) + index(1)                      = 3
///   text        opcode(1) + msPerChar(1) + length(1) + payload    = 3 + n
///   repeat      opcode(1) + count(1) + bodyLength(2) + body       = 4 + body
///   macro       id(1) + nameLength(1) + name + stepCount(1)       = 3 + name + steps
extension MacroStep {
    var compiledSize: Int {
        switch self {
        case .keystroke: return 5
        case .delay: return 3
        case .layer: return 3
        case .text(let s, _, _): return 3 + s.utf8.count
        case .repeatBlock(_, let steps): return 4 + steps.reduce(0) { $0 + $1.compiledSize }
        case .raw: return 0 // never compiled, so it costs no board memory
        }
    }

    /// Milliseconds this step is expected to take when the board runs it.
    var estimatedDurationMs: Int {
        switch self {
        case .keystroke(_, _, let holdMs): return holdMs
        case .delay(let ms): return ms
        case .text(let s, _, let msPerChar): return s.count * msPerChar
        case .layer: return 0
        case .repeatBlock(let count, let steps):
            return count * steps.reduce(0) { $0 + $1.estimatedDurationMs }
        case .raw: return 0
        }
    }
}

extension MacroDefinition {
    var compiledSize: Int {
        3 + name.utf8.count + steps.reduce(0) { $0 + $1.compiledSize }
    }

    var estimatedDurationMs: Int {
        steps.reduce(0) { $0 + $1.estimatedDurationMs }
    }

    /// "0.52 s est." as shown under the macro name in the canvas header.
    var estimatedDurationLabel: String {
        String(format: "%.2f s est.", Double(estimatedDurationMs) / 1000)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --build-system native --filter MacroTests`
Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/SMKConfigurator/Model/Macro.swift Tests/SMKConfiguratorTests/MacroTests.swift
git commit -m "Compute macro compiled size and estimated duration"
```

---

### Task 3: The `macro:N` action token

**Files:**
- Modify: `Sources/SMKConfigurator/Model/ActionToken.swift`
- Test: `Tests/SMKConfiguratorTests/ActionTokenTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `ActionToken.macro(Int)`, canonical string `macro:<id>`, display label `M<id>`

- [ ] **Step 1: Write the failing test**

Append to the `ActionTokenTests` suite in `Tests/SMKConfiguratorTests/ActionTokenTests.swift`:

```swift
    @Test("macro tokens round-trip through macro:<id>", arguments: 0...31)
    func macroRoundTrip(id: Int) {
        let token = ActionToken.macro(id)
        #expect(token.canonicalString == "macro:\(id)")
        #expect(ActionToken.parse(token.canonicalString) == token)
        #expect(token.displayLabel == "M\(id)")
    }

    @Test("a macro token with a non-numeric id is preserved as raw")
    func malformedMacroStaysRaw() {
        #expect(ActionToken.parse("macro:abc") == .raw("macro:abc"))
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --build-system native --filter ActionTokenTests`
Expected: compile failure — `type 'ActionToken' has no member 'macro'`.

- [ ] **Step 3: Write minimal implementation**

In `Sources/SMKConfigurator/Model/ActionToken.swift`, add the case after `toggleConnection`:

```swift
    /// Runs the macro stored in slot `n`. Must stay in lockstep with
    /// `KeyAction.fromCString` in the firmware's `LayerEngine.swift`.
    case macro(Int)
```

Add to `canonicalString`, before the `.raw` case:

```swift
        case .macro(let n): return "macro:\(n)"
```

Add to `displayLabel`, before the `.raw` case. Note this is the one token whose
label is not self-sufficient — a macro keycap should read its name, which needs a
document lookup, so `KeyCapView` resolves it separately (Task 14):

```swift
        case .macro(let n): return "M\(n)"
```

Add to `parse`, before the final `return .raw(s)`:

```swift
        if s.hasPrefix("macro:"), let n = Int(s.dropFirst(6)) {
            return .macro(n)
        }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --build-system native --filter ActionTokenTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SMKConfigurator/Model/ActionToken.swift Tests/SMKConfiguratorTests/ActionTokenTests.swift
git commit -m "Add the macro:N action token"
```

---

### Task 4: Macros in the document, without churning existing files

`macros` must be **optional** so that opening and saving the reference
`~/esp/SMK/keymap.json` — which has no macros key — does not add `"macros": []`
to it. `JSONEncoder` omits a nil optional entirely.

**Files:**
- Modify: `Sources/SMKConfigurator/Model/KeymapDocument.swift`
- Test: `Tests/SMKConfiguratorTests/KeymapDocumentTests.swift`

**Interfaces:**
- Consumes: `MacroDefinition` from Task 1
- Produces: `KeymapDocument.macros: [MacroDefinition]?`, `KeymapDocument.macroList: [MacroDefinition]`, `KeymapDocument.nextMacroID: Int`

- [ ] **Step 1: Write the failing test**

Append to the suite in `Tests/SMKConfiguratorTests/KeymapDocumentTests.swift`:

```swift
    @Test("a document with no macros key does not gain one on save")
    func absentMacrosKeyStaysAbsent() throws {
        let json = """
        {"matrix":{"rows":[0],"cols":[1],"colsAreDriven":1},"layers":[[["key:a"]]]}
        """
        let doc = try JSONDecoder().decode(KeymapDocument.self, from: Data(json.utf8))
        #expect(doc.macros == nil)

        let data = try JSONEncoder().encode(doc)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(object["macros"] == nil)
    }

    @Test("macros survive a document round-trip")
    func macrosRoundTrip() throws {
        var doc = KeymapDocument(
            matrix: .init(rows: [0], cols: [1], colsAreDriven: 1),
            layers: [[["key:a"]]]
        )
        doc.macros = [MacroDefinition(id: 0, name: "Hi", steps: [.delay(ms: 5)])]

        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(KeymapDocument.self, from: data)
        #expect(decoded.macros == doc.macros)
    }

    @Test("macroList reads nil as empty")
    func macroListTreatsNilAsEmpty() {
        let doc = KeymapDocument(
            matrix: .init(rows: [0], cols: [1], colsAreDriven: 1),
            layers: [[["key:a"]]]
        )
        #expect(doc.macroList.isEmpty)
    }

    @Test("nextMacroID fills the lowest free slot")
    func nextMacroIDFillsGaps() {
        var doc = KeymapDocument(
            matrix: .init(rows: [0], cols: [1], colsAreDriven: 1),
            layers: [[["key:a"]]]
        )
        #expect(doc.nextMacroID == 0)
        doc.macros = [
            MacroDefinition(id: 0, name: "a", steps: []),
            MacroDefinition(id: 2, name: "c", steps: []),
        ]
        #expect(doc.nextMacroID == 1)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --build-system native --filter KeymapDocumentTests`
Expected: compile failure — `value of type 'KeymapDocument' has no member 'macros'`.

- [ ] **Step 3: Write minimal implementation**

In `Sources/SMKConfigurator/Model/KeymapDocument.swift`, add after `var layers`:

```swift
    /// Macros, added by this editor and read by the firmware's macro player.
    ///
    /// Optional rather than defaulted-empty on purpose: a `keymap.json`
    /// written before macros existed must not gain a `"macros": []` key
    /// merely from being opened and saved. `JSONEncoder` omits a nil
    /// optional entirely, so the lossless-save guarantee holds.
    var macros: [MacroDefinition]?

    /// `macros` with nil read as empty, for call sites that only read.
    var macroList: [MacroDefinition] { macros ?? [] }

    /// The lowest unused slot number, so deleting a macro frees its slot for
    /// reuse rather than leaving a permanent hole.
    var nextMacroID: Int {
        let used = Set(macroList.map(\.id))
        var candidate = 0
        while used.contains(candidate) { candidate += 1 }
        return candidate
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --build-system native --filter KeymapDocumentTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SMKConfigurator/Model/KeymapDocument.swift Tests/SMKConfiguratorTests/KeymapDocumentTests.swift
git commit -m "Carry macros in the keymap document without churning existing files"
```

---

### Task 5: Capacity model

Implements contract C2. The `CAPS` device command itself belongs to sub-project 3;
this task builds the model and the five states so the UI has real behaviour to
render, defaulting to the floor profile until a board reports otherwise.

**Files:**
- Create: `Sources/SMKConfigurator/Model/MacroCapacity.swift`
- Test: `Tests/SMKConfiguratorTests/MacroCapacityTests.swift`

**Interfaces:**
- Consumes: `MacroDefinition` from Task 1
- Produces: `MacroCapacity`, `MacroCapacity.floor`, `MacroCapacitySource`, `MacroBudget`, `MacroBudget.init(capacity:source:macros:)`

- [ ] **Step 1: Write the failing test**

Create `Tests/SMKConfiguratorTests/MacroCapacityTests.swift`:

```swift
import Testing
@testable import SMKConfigurator

@Suite("Macro capacity degrades and improves with whatever the board reports")
struct MacroCapacityTests {
    private func macro(_ id: Int, bytes: Int) -> MacroDefinition {
        // 3 header bytes + 1 name byte + text step (3 + n) == bytes
        let payload = String(repeating: "x", count: max(0, bytes - 7))
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
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --build-system native --filter MacroCapacityTests`
Expected: compile failure — `cannot find 'MacroBudget' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/SMKConfigurator/Model/MacroCapacity.swift`:

```swift
import Foundation

/// How much macro storage a board has. Reported by the board rather than
/// hardcoded, because the supported ports range from SAMD21-class parts with
/// almost no spare flash to ESP32-C6 and RP2040 with plenty. See contract C2
/// in `docs/superpowers/specs/2026-08-20-macro-creation-design.md`.
struct MacroCapacity: Codable, Equatable, Hashable {
    var macroBytes: Int
    var macroSlots: Int

    /// The smallest board this editor assumes when it has never spoken to
    /// one. Deliberately conservative: an under-promise is corrected upward
    /// the moment a real board answers, whereas an over-promise lets someone
    /// build a macro that can never be flashed. Superseded by any real
    /// device report.
    static let floor = MacroCapacity(macroBytes: 1024, macroSlots: 8)
}

/// Where the capacity numbers in front of the user came from.
enum MacroCapacitySource: Equatable, Hashable {
    /// A connected board reported them just now.
    case device
    /// Remembered from the last time this board was connected.
    case lastKnown
    /// No board has ever been seen; `MacroCapacity.floor` is in use.
    case floor
}

/// Capacity, current usage, and whether flashing is allowed. Purely derived —
/// build a fresh one whenever the macro list or the capacity changes.
struct MacroBudget: Equatable {
    var capacity: MacroCapacity
    var source: MacroCapacitySource
    var usedBytes: Int
    var usedSlots: Int

    init(capacity: MacroCapacity, source: MacroCapacitySource, macros: [MacroDefinition]) {
        self.capacity = capacity
        self.source = source
        self.usedBytes = macros.reduce(0) { $0 + $1.compiledSize }
        self.usedSlots = macros.count
    }

    var totalBytes: Int { capacity.macroBytes }

    /// True when the numbers aren't from a board that's connected right now,
    /// so the UI can label the meter honestly.
    var isEstimate: Bool { source != .device }

    /// 0...1, clamped so an over-budget macro fills the track rather than
    /// drawing past its end.
    var fillFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1.0, max(0.0, Double(usedBytes) / Double(totalBytes)))
    }

    /// Why flashing is unavailable, or nil when it's fine. Never blocks
    /// editing or saving to disk — only the upload.
    var blockReason: String? {
        if capacity.macroBytes == 0 || capacity.macroSlots == 0 {
            return "This board has no macro memory."
        }
        if usedSlots > capacity.macroSlots {
            return "This board has \(capacity.macroSlots) macro slots; \(usedSlots) macros are defined."
        }
        if usedBytes > capacity.macroBytes {
            return "Macros exceed this board's memory by \(usedBytes - capacity.macroBytes) bytes."
        }
        return nil
    }

    var canFlash: Bool { blockReason == nil }

    /// "148 of 384 bytes · slot 3" in the palette column's SLOT section.
    func summaryLabel(slot: Int) -> String {
        let estimate = isEstimate ? " (estimated)" : ""
        return "\(usedBytes) of \(totalBytes) bytes · slot \(slot)\(estimate)"
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --build-system native --filter MacroCapacityTests`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/SMKConfigurator/Model/MacroCapacity.swift Tests/SMKConfiguratorTests/MacroCapacityTests.swift
git commit -m "Model macro capacity as something the board reports"
```

---

### Task 6: Macro editing on EditorState

All the mutations the editor's buttons need, tested without any view involved.

**Files:**
- Modify: `Sources/SMKConfigurator/Model/EditorState.swift`
- Test: `Tests/SMKConfiguratorTests/MacroEditingTests.swift`

**Interfaces:**
- Consumes: `MacroDefinition`, `MacroStep`, `MacroBudget`, `KeymapDocument.nextMacroID`
- Produces: `RailMode.macros`, `MacroWorkspace`, and on `EditorState`: `macroWorkspace`, `selectedStepIndex`, `macroCapacity`, `macroCapacitySource`, `macroBudget`, `currentMacro`, `createMacro()`, `openMacro(id:)`, `closeMacro()`, `deleteMacro(id:)`, `updateMacro(_:)`, `appendStep(_:)`, `insertStepAfterSelection(_:)`, `moveStep(from:to:)`, `deleteStep(at:)`, `macroName(for:)`

- [ ] **Step 1: Write the failing test**

Create `Tests/SMKConfiguratorTests/MacroEditingTests.swift`:

```swift
import Testing
@testable import SMKConfigurator

@Suite("Editing macros on EditorState")
@MainActor
struct MacroEditingTests {
    private func editor() -> EditorState {
        let editor = EditorState()
        editor.document = KeymapDocument(
            matrix: .init(rows: [0], cols: [1], colsAreDriven: 1),
            layers: [[["none"]]]
        )
        return editor
    }

    @Test("creating a macro takes the lowest free slot and opens it")
    func createMacroOpensIt() {
        let e = editor()
        e.createMacro()
        #expect(e.document.macroList.count == 1)
        #expect(e.document.macroList[0].id == 0)
        #expect(e.macroWorkspace == .editor(id: 0))
        #expect(e.isDirty)
    }

    @Test("closing the editor returns to the library")
    func closeReturnsToLibrary() {
        let e = editor()
        e.createMacro()
        e.closeMacro()
        #expect(e.macroWorkspace == .library)
    }

    @Test("appending a step adds it at the end and selects it")
    func appendSelectsNewStep() {
        let e = editor()
        e.createMacro()
        e.appendStep(.delay(ms: 100))
        e.appendStep(.delay(ms: 200))
        #expect(e.document.macroList[0].steps.count == 2)
        #expect(e.selectedStepIndex == 1)
    }

    @Test("a step inserts after the selection, not at the end")
    func insertAfterSelection() {
        let e = editor()
        e.createMacro()
        e.appendStep(.delay(ms: 1))
        e.appendStep(.delay(ms: 3))
        e.selectedStepIndex = 0
        e.insertStepAfterSelection(.delay(ms: 2))
        #expect(e.document.macroList[0].steps == [.delay(ms: 1), .delay(ms: 2), .delay(ms: 3)])
        #expect(e.selectedStepIndex == 1)
    }

    @Test("moving a step past either end is a no-op rather than a crash")
    func moveClampsAtBoundaries() {
        let e = editor()
        e.createMacro()
        e.appendStep(.delay(ms: 1))
        e.appendStep(.delay(ms: 2))

        e.moveStep(from: 0, to: -1)
        #expect(e.document.macroList[0].steps == [.delay(ms: 1), .delay(ms: 2)])

        e.moveStep(from: 1, to: 2)
        #expect(e.document.macroList[0].steps == [.delay(ms: 1), .delay(ms: 2)])

        e.moveStep(from: 0, to: 1)
        #expect(e.document.macroList[0].steps == [.delay(ms: 2), .delay(ms: 1)])
        #expect(e.selectedStepIndex == 1)
    }

    @Test("deleting the last step selects the new last step")
    func deleteAdjustsSelection() {
        let e = editor()
        e.createMacro()
        e.appendStep(.delay(ms: 1))
        e.appendStep(.delay(ms: 2))
        e.selectedStepIndex = 1
        e.deleteStep(at: 1)
        #expect(e.document.macroList[0].steps == [.delay(ms: 1)])
        #expect(e.selectedStepIndex == 0)
    }

    @Test("deleting the only step clears the selection")
    func deleteLastClearsSelection() {
        let e = editor()
        e.createMacro()
        e.appendStep(.delay(ms: 1))
        e.deleteStep(at: 0)
        #expect(e.selectedStepIndex == nil)
    }

    @Test("deleting a macro frees its slot and returns to the library")
    func deleteMacroFreesSlot() {
        let e = editor()
        e.createMacro()   // id 0
        e.closeMacro()
        e.createMacro()   // id 1
        e.deleteMacro(id: 0)
        #expect(e.document.macroList.map(\.id) == [1])
        #expect(e.document.nextMacroID == 0)
        #expect(e.macroWorkspace == .library)
    }

    @Test("macroName resolves a slot to its name for keycap display")
    func macroNameResolves() {
        let e = editor()
        e.createMacro()
        e.updateMacro(MacroDefinition(id: 0, name: "Build & deploy", steps: []))
        #expect(e.macroName(for: 0) == "Build & deploy")
        #expect(e.macroName(for: 9) == nil)
    }

    @Test("the budget reflects the document's macros")
    func budgetTracksDocument() {
        let e = editor()
        e.createMacro()
        e.updateMacro(MacroDefinition(id: 0, name: "ab",
                                      steps: [.delay(ms: 5)]))
        // 3 header + 2 name + 3 step
        #expect(e.macroBudget.usedBytes == 8)
        #expect(e.macroBudget.usedSlots == 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --build-system native --filter MacroEditingTests`
Expected: compile failure — `cannot find 'MacroWorkspace' in scope`.

- [ ] **Step 3: Write minimal implementation**

In `Sources/SMKConfigurator/Model/EditorState.swift`, change the `RailMode` case list at line 38:

```swift
    case key, designs, themes, device, macros
```

Add below the `RailMode` declaration:

```swift
/// Macros mode is the only rail mode with sub-states: the library takes the
/// whole workspace, and opening a macro swaps it for the step editor. Every
/// other rail mode renders one fixed layout.
enum MacroWorkspace: Equatable, Hashable {
    case library
    case editor(id: Int)

    var openMacroID: Int? {
        if case .editor(let id) = self { return id }
        return nil
    }
}
```

Add these stored properties alongside the other UI state (near `selectedKeyPosition`):

```swift
    var macroWorkspace: MacroWorkspace = .library
    /// Which step the inspector is editing, or nil when the macro is empty.
    var selectedStepIndex: Int? = nil
    /// The last capacity a board reported, or the floor profile until one does.
    var macroCapacity: MacroCapacity = .floor
    var macroCapacitySource: MacroCapacitySource = .floor
```

Add a `// MARK: - Macro editing` section at the end of the class:

```swift
    // MARK: - Macro editing

    var macroBudget: MacroBudget {
        MacroBudget(capacity: macroCapacity,
                    source: macroCapacitySource,
                    macros: document.macroList)
    }

    /// The macro currently open in the editor, if any. Named `currentMacro`
    /// rather than `openMacro` because a property and a method cannot share
    /// an identifier — `openMacro(id:)` below is the verb.
    var currentMacro: MacroDefinition? {
        guard let id = macroWorkspace.openMacroID else { return nil }
        return document.macroList.first { $0.id == id }
    }

    /// The name for `macro:<id>`, used by `KeyCapView` — the one token whose
    /// label isn't self-contained. Nil when the slot holds no macro, so the
    /// keycap can fall back to the token's own "M<id>".
    func macroName(for id: Int) -> String? {
        document.macroList.first { $0.id == id }?.name
    }

    func createMacro() {
        let macro = MacroDefinition(id: document.nextMacroID, name: "New macro", steps: [])
        document.macros = document.macroList + [macro]
        macroWorkspace = .editor(id: macro.id)
        selectedStepIndex = nil
        isDirty = true
    }

    func openMacro(id: Int) {
        macroWorkspace = .editor(id: id)
        selectedStepIndex = document.macroList.first { $0.id == id }?.steps.isEmpty == false ? 0 : nil
    }

    func closeMacro() {
        macroWorkspace = .library
        selectedStepIndex = nil
    }

    func deleteMacro(id: Int) {
        document.macros = document.macroList.filter { $0.id != id }
        if document.macroList.isEmpty { document.macros = nil }
        if macroWorkspace.openMacroID == id { closeMacro() }
        isDirty = true
    }

    func updateMacro(_ macro: MacroDefinition) {
        guard let index = document.macroList.firstIndex(where: { $0.id == macro.id }) else { return }
        var list = document.macroList
        list[index] = macro
        document.macros = list
        isDirty = true
    }

    /// Applies `transform` to the macro currently open, if any.
    private func mutateOpenMacro(_ transform: (inout MacroDefinition) -> Void) {
        guard var macro = currentMacro else { return }
        transform(&macro)
        updateMacro(macro)
    }

    func appendStep(_ step: MacroStep) {
        mutateOpenMacro { $0.steps.append(step) }
        selectedStepIndex = (currentMacro?.steps.count ?? 1) - 1
    }

    /// Inserts after the selected step, which is how a position is chosen
    /// without drag-and-drop. With nothing selected, appends.
    func insertStepAfterSelection(_ step: MacroStep) {
        guard let selected = selectedStepIndex, currentMacro != nil else {
            appendStep(step)
            return
        }
        let target = selected + 1
        mutateOpenMacro { $0.steps.insert(step, at: min(target, $0.steps.count)) }
        selectedStepIndex = target
    }

    func moveStep(from source: Int, to destination: Int) {
        guard let macro = currentMacro,
              macro.steps.indices.contains(source),
              macro.steps.indices.contains(destination)
        else { return }
        mutateOpenMacro {
            let step = $0.steps.remove(at: source)
            $0.steps.insert(step, at: destination)
        }
        selectedStepIndex = destination
    }

    func deleteStep(at index: Int) {
        guard let macro = currentMacro, macro.steps.indices.contains(index) else { return }
        mutateOpenMacro { $0.steps.remove(at: index) }
        let remaining = currentMacro?.steps.count ?? 0
        selectedStepIndex = remaining == 0 ? nil : min(index, remaining - 1)
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --build-system native --filter MacroEditingTests`
Expected: PASS, 10 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/SMKConfigurator/Model/EditorState.swift Tests/SMKConfiguratorTests/MacroEditingTests.swift
git commit -m "Add macro editing operations to EditorState"
```

---

### Task 7: Send macros to the device

`sendToDevice()` currently uploads `{"layers": [...]}` only, via
`encodeLayersJSON`. Macros must ride along, and the upload must refuse when the
budget says it can't fit.

**Files:**
- Modify: `Sources/SMKConfigurator/Model/EditorState.swift:261-267`
- Test: `Tests/SMKConfiguratorTests/MacroEditingTests.swift`

**Interfaces:**
- Consumes: `MacroBudget` from Task 5, `document.macros` from Task 4
- Produces: `EditorState.encodeUploadJSON(layers:macros:) throws -> String`

- [ ] **Step 1: Write the failing test**

Append to the `MacroEditingTests` suite:

```swift
    @Test("the upload payload carries macros alongside layers")
    func uploadPayloadIncludesMacros() throws {
        let e = editor()
        e.createMacro()
        e.updateMacro(MacroDefinition(id: 0, name: "Hi", steps: [.delay(ms: 5)]))

        let json = try e.encodeUploadJSON(layers: e.document.layers, macros: e.document.macros)
        #expect(json.contains("\"macros\""))
        #expect(json.contains("\"layers\""))
    }

    @Test("a document with no macros uploads no macros key")
    func uploadOmitsAbsentMacros() throws {
        let e = editor()
        let json = try e.encodeUploadJSON(layers: e.document.layers, macros: nil)
        #expect(json.contains("\"macros\"") == false)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --build-system native --filter MacroEditingTests`
Expected: compile failure — `value of type 'EditorState' has no member 'encodeUploadJSON'`.

- [ ] **Step 3: Write minimal implementation**

Replace `encodeLayersJSON` in `Sources/SMKConfigurator/Model/EditorState.swift` with:

```swift
    /// The JSON the board receives. Matrix data is deliberately absent — the
    /// firmware's matrix stays compiled in — but macros travel with the
    /// layers, since one upload has to leave the board self-consistent.
    /// `macros` is omitted entirely when nil, so a macro-free keymap uploads
    /// byte-identically to how it did before macros existed.
    func encodeUploadJSON(layers: [[[String]]], macros: [MacroDefinition]?) throws -> String {
        struct UploadPayload: Encodable {
            let layers: [[[String]]]
            let macros: [MacroDefinition]?
        }
        let data = try JSONEncoder().encode(UploadPayload(layers: layers, macros: macros))
        guard let json = String(data: data, encoding: .utf8) else {
            throw DeviceTransportError.encodingFailed
        }
        return json
    }
```

Update the single call site inside `sendToDevice()` from
`try encodeLayersJSON(document.layers)` to
`try encodeUploadJSON(layers: document.layers, macros: document.macros)`.
Find it with `grep -n "encodeLayersJSON" Sources/SMKConfigurator/Model/EditorState.swift`.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --build-system native --filter MacroEditingTests`
Expected: PASS, 12 tests.

Then run the whole suite to be sure nothing else called the old name:
Run: `swift test --build-system native`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SMKConfigurator/Model/EditorState.swift Tests/SMKConfiguratorTests/MacroEditingTests.swift
git commit -m "Send macros to the board with the layers"
```

---

### Task 8: The macros rail icon

**Files:**
- Modify: `Sources/SMKConfigurator/Views/AppIcon.swift`, `Sources/SMKConfigurator/Views/IconRailView.swift`, `Scripts/generate-icons.sh`
- Test: `Tests/SMKConfiguratorTests/IconLoaderTests.swift`

**Interfaces:**
- Consumes: `RailMode.macros` from Task 6
- Produces: `AppIcon.macros`

- [ ] **Step 1: Write the failing test**

Append to the suite in `Tests/SMKConfiguratorTests/IconLoaderTests.swift`. If
that suite already iterates `AppIcon.allCases`, this is redundant but harmless —
keep it, since it names the expected string explicitly:

```swift
    @Test("the macros rail icon has a fallback label")
    func macrosHasFallbackLabel() {
        #expect(AppIcon.macros.fallbackLabel == "MAC")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --build-system native --filter IconLoaderTests`
Expected: compile failure — `type 'AppIcon' has no member 'macros'`.

- [ ] **Step 3: Write minimal implementation**

In `Sources/SMKConfigurator/Views/AppIcon.swift`, add `case macros` to the enum
and `"MAC"` to `fallbackLabel`, matching the surrounding style exactly.

In `Scripts/generate-icons.sh`, alongside the other rail icons, add:

```bash
render_macos_icon macros "wand.and.stars" "$RAIL_SIZE"
```

plus the Windows line using Fluent `Wand/SVG/ic_fluent_wand_24_regular.svg` and
the Linux line using Adwaita `actions/applications-utilities-symbolic.svg`, in
the same form the neighbouring icons use.

Run `bash Scripts/generate-icons.sh` to produce the PNGs. It needs
`rsvg-convert` (`brew install librsvg`) plus Xcode CLT. **If it fails**, do not
hand-copy the PNG from the design handoff — commit the code change with the
fallback label working and note the icon needs regenerating.

In `Sources/SMKConfigurator/Views/IconRailView.swift`, add after the device button:

```swift
            RailButton(icon: .macros, tooltip: "Macros", isActive: mode == .macros) {
                mode = .macros
            }
```

Match the exact call shape of the neighbouring buttons — read them first.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --build-system native --filter IconLoaderTests`
Expected: PASS.

Then: `swift build --target SMKConfigurator --build-system native`
Expected: builds. `ContentView` will still be missing `.macros` cases if its
switches are exhaustive — if so, add `case .macros: EmptyView()` placeholders to
each of the three column properties for now; Task 12 fills them in.

- [ ] **Step 5: Commit**

```bash
git add Sources/SMKConfigurator/Views/AppIcon.swift Sources/SMKConfigurator/Views/IconRailView.swift Sources/SMKConfigurator/Views/ContentView.swift Scripts/generate-icons.sh Sources/SMKConfigurator/Resources
git commit -m "Add the macros rail destination"
```

---

### Task 9: The macro library table

**Files:**
- Create: `Sources/SMKConfigurator/Views/MacroLibraryView.swift`
- Test: `Tests/SMKConfiguratorTests/MacroEditingTests.swift`

**Interfaces:**
- Consumes: `EditorState.macroBudget`, `document.macroList`, `openMacro(id:)`, `createMacro()`
- Produces: `MacroLibraryView`, `MacroLibraryRow` (a testable per-row view model), `MacroLibraryRow.init(macro:document:)`

Row derivation is testable; the view is not. Put every derived string in
`MacroLibraryRow` and test that, then render it.

- [ ] **Step 1: Write the failing test**

Append to the `MacroEditingTests` suite:

```swift
    @Test("a library row derives its trigger from wherever the macro is bound")
    func rowFindsTrigger() {
        var doc = KeymapDocument(
            matrix: .init(rows: [0], cols: [1, 2], colsAreDriven: 1),
            layers: [[["none", "macro:3"]]]
        )
        doc.macros = [MacroDefinition(id: 3, name: "Build", steps: [.delay(ms: 5)])]

        let row = MacroLibraryRow(macro: doc.macroList[0], document: doc)
        #expect(row.name == "Build")
        #expect(row.stepCount == 1)
        #expect(row.isBound)
        #expect(row.layerLabel == "Layer 0")
    }

    @Test("an unbound macro says so rather than inventing a trigger")
    func rowHandlesUnbound() {
        var doc = KeymapDocument(
            matrix: .init(rows: [0], cols: [1], colsAreDriven: 1),
            layers: [[["none"]]]
        )
        doc.macros = [MacroDefinition(id: 3, name: "Orphan", steps: [])]

        let row = MacroLibraryRow(macro: doc.macroList[0], document: doc)
        #expect(row.isBound == false)
        #expect(row.triggerLabel == "Unbound")
        #expect(row.layerLabel == "—")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --build-system native --filter MacroEditingTests`
Expected: compile failure — `cannot find 'MacroLibraryRow' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/SMKConfigurator/Views/MacroLibraryView.swift`. First the row
model, then the view:

```swift
import Foundation
import SwiftCrossUI

/// One row of the library table, with every displayed string derived up front
/// so the view itself stays declarative and the derivation stays testable.
struct MacroLibraryRow: Identifiable, Equatable {
    var id: Int
    var name: String
    var stepCount: Int
    var byteCount: Int
    var isBound: Bool
    var triggerLabel: String
    var layerLabel: String

    init(macro: MacroDefinition, document: KeymapDocument) {
        self.id = macro.id
        self.name = macro.name
        self.stepCount = macro.steps.count
        self.byteCount = macro.compiledSize

        // Find the first cell in any layer bound to this macro. A macro can
        // legitimately be bound more than once; the first is enough to answer
        // "can I reach this?", which is what the column is for.
        let token = ActionToken.macro(macro.id).canonicalString
        var found: (layer: Int, row: Int, col: Int)? = nil
        outer: for (l, layer) in document.layers.enumerated() {
            for (r, row) in layer.enumerated() {
                for (c, cell) in row.enumerated() where cell == token {
                    found = (l, r, c)
                    break outer
                }
            }
        }

        if let found {
            self.isBound = true
            self.triggerLabel = "R\(found.row)C\(found.col)"
            self.layerLabel = "Layer \(found.layer)"
        } else {
            self.isBound = false
            self.triggerLabel = "Unbound"
            self.layerLabel = "—"
        }
    }
}
```

Then the view below it, in the same file. Build it from the existing primitives
(`SectionHeader`, `TapTarget`, `ToolbarPill`) and `Chrome` tokens only:

- A header row: "Macros" at 19px semibold, the budget summary at 11px
  `chrome.textTertiary`, then right-aligned "Record new" (disabled — see Task 13)
  and "New macro" (`chrome.accent`, calls `editor.createMacro()`).
- A column-header row at 11px bold uppercase `chrome.textTertiary`:
  MACRO / TRIGGER / KIND / STEPS / LAYER / BYTES.
- One `TapTarget` per row calling `editor.openMacro(id:)`, background
  `chrome.column`, using the `MacroLibraryRow` fields. Remember the ZStack rule:
  pass the hover/selected fill in as `background:`, never branch inside.
- When `editor.document.macroList.isEmpty`, show a centred 12px
  `chrome.textTertiary` line: "No macros yet. Create one to place it on a key."

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --build-system native --filter MacroEditingTests`
Expected: PASS, 14 tests.

Then: `swift build --target SMKConfigurator --build-system native` — must build.

- [ ] **Step 5: Commit**

```bash
git add Sources/SMKConfigurator/Views/MacroLibraryView.swift Tests/SMKConfiguratorTests/MacroEditingTests.swift
git commit -m "Add the macro library table"
```

---

### Task 10: Step palette column and canvas header

**Files:**
- Create: `Sources/SMKConfigurator/Views/MacroEditorViews.swift`
- Test: `Tests/SMKConfiguratorTests/MacroEditingTests.swift`

**Interfaces:**
- Consumes: `MacroStep`, `MacroBudget`, `EditorState.insertStepAfterSelection(_:)`, `closeMacro()`
- Produces: `MacroStepType` (the five palette entries), `MacroStepPaletteView`, `MacroCanvasHeaderView`

- [ ] **Step 1: Write the failing test**

Append to the `MacroEditingTests` suite:

```swift
    @Test("every palette type makes a step of its own kind")
    func paletteTypesProduceMatchingSteps() {
        for type in MacroStepType.allCases {
            #expect(type.makeStep().typeCode == type.badge)
        }
    }

    @Test("the palette offers exactly the five step types, in design order")
    func paletteOrder() {
        #expect(MacroStepType.allCases.map(\.badge) == ["KEY", "TXT", "DLY", "LYR", "RPT"])
        #expect(MacroStepType.allCases.map(\.label)
                == ["Keystroke", "Type text", "Delay", "Switch layer", "Repeat block"])
    }

    @Test("repeat blocks can't nest, so the palette hides RPT inside one")
    func repeatIsHiddenInsideARepeat() {
        #expect(MacroStepType.available(insideRepeatBlock: true).map(\.badge)
                == ["KEY", "TXT", "DLY", "LYR"])
        #expect(MacroStepType.available(insideRepeatBlock: false).count == 5)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --build-system native --filter MacroEditingTests`
Expected: compile failure — `cannot find 'MacroStepType' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/SMKConfigurator/Views/MacroEditorViews.swift`:

```swift
import Foundation
import SwiftCrossUI

/// The five entries in the ADD STEP palette. Separate from `MacroStep`
/// because the palette needs a stable, ordered, badge-coloured list, while
/// `MacroStep` is a value with payloads.
enum MacroStepType: String, CaseIterable, Identifiable, Hashable {
    case keystroke, text, delay, layer, repeatBlock

    var id: String { rawValue }

    var badge: String {
        switch self {
        case .keystroke: return "KEY"
        case .text: return "TXT"
        case .delay: return "DLY"
        case .layer: return "LYR"
        case .repeatBlock: return "RPT"
        }
    }

    var label: String {
        switch self {
        case .keystroke: return "Keystroke"
        case .text: return "Type text"
        case .delay: return "Delay"
        case .layer: return "Switch layer"
        case .repeatBlock: return "Repeat block"
        }
    }

    /// Badge colours reuse the keymap view's keycap palette rather than
    /// introducing new ones. `nil` means the neutral pill background.
    var badgeColorHex: String? {
        switch self {
        case .keystroke: return "#FFFFFF"
        case .text: return "#C9C9C9"
        case .delay: return "#F7DA71"
        case .layer: return "#F3A75C"
        case .repeatBlock: return nil
        }
    }

    /// A new step of this type with the defaults the design shows.
    func makeStep() -> MacroStep {
        switch self {
        case .keystroke: return .keystroke(mods: [], key: .a, holdMs: 40)
        case .text: return .text("", delivery: .keystrokes, msPerChar: 12)
        case .delay: return .delay(ms: 100)
        case .layer: return .layer(op: .momentary, n: 1)
        case .repeatBlock: return .repeatBlock(count: 2, steps: [])
        }
    }

    /// Repeat blocks don't nest (see the spec), so RPT disappears from the
    /// palette while the selection is inside one.
    static func available(insideRepeatBlock: Bool) -> [MacroStepType] {
        insideRepeatBlock ? allCases.filter { $0 != .repeatBlock } : allCases
    }
}
```

Then add the two views in the same file:

`MacroStepPaletteView` — a 212pt column with `SectionHeader("ADD STEP")` over one
`TapTarget` per available type (28pt badge + label, calling
`editor.insertStepAfterSelection(type.makeStep())`); `SectionHeader("CAPTURE")`
over a disabled "Record from board" button (Task 13); `SectionHeader("SLOT")`
over a 5pt track showing `editor.macroBudget.fillFraction` with
`summaryLabel(slot:)` beneath; a `Spacer`; and a "Back to library" button calling
`editor.closeMacro()`.

`MacroCanvasHeaderView` — the macro name at 19px semibold, the metadata line
`"macro:\(id) · \(steps.count) steps · \(macro.estimatedDurationLabel)"` at 12px
monospace `chrome.textSecondary`, and right-aligned "Test run" (pill) and
**"Save"** (`chrome.accent`). Note the button reads Save, not "Save & flash".

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --build-system native --filter MacroEditingTests`
Expected: PASS, 17 tests.

Then: `swift build --target SMKConfigurator --build-system native` — must build.

- [ ] **Step 5: Commit**

```bash
git add Sources/SMKConfigurator/Views/MacroEditorViews.swift Tests/SMKConfiguratorTests/MacroEditingTests.swift
git commit -m "Add the macro step palette and canvas header"
```

---

### Task 11: The sequence row

The fiddliest view: a badge, a payload that differs per step type, right-aligned
metadata, and — since there is no drag — reorder and delete controls.

**Files:**
- Create: `Sources/SMKConfigurator/Views/MacroStepRowView.swift`
- Test: `Tests/SMKConfiguratorTests/MacroEditingTests.swift`

**Interfaces:**
- Consumes: `MacroStep`, `EditorState.moveStep(from:to:)`, `deleteStep(at:)`
- Produces: `MacroStepRowView`, `MacroStep.payloadSummary`, `MacroStep.metadataLabel`

- [ ] **Step 1: Write the failing test**

Append to the `MacroTests` suite in `Tests/SMKConfiguratorTests/MacroTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --build-system native --filter MacroTests`
Expected: compile failure — `value of type 'MacroStep' has no member 'payloadSummary'`.

- [ ] **Step 3: Write minimal implementation**

Append to `Sources/SMKConfigurator/Model/Macro.swift`:

```swift
// MARK: - Row display

extension MacroStep {
    /// The middle column of a sequence row.
    var payloadSummary: String {
        switch self {
        case .keystroke(let mods, let key, _):
            let parts = mods.map(\.displayLabel) + (key.map { [$0.displayLabel] } ?? [])
            return parts.joined(separator: " + ")
        case .text(let s, _, _):
            return "\"\(s)\""
        case .delay(let ms):
            return "Wait \(ms) ms"
        case .layer(let op, let n):
            return op == .momentary
                ? "Momentary layer \(n) while running"
                : "Toggle layer \(n)"
        case .repeatBlock(let count, let steps):
            let noun = steps.count == 1 ? "step" : "steps"
            return "Repeat \(steps.count) \(noun) \(count) times"
        case .raw:
            return "Unsupported step (kept on save)"
        }
    }

    /// The right-aligned metadata of a sequence row. Empty when the payload
    /// already says everything.
    var metadataLabel: String {
        switch self {
        case .keystroke(_, _, let holdMs): return "hold \(holdMs) ms"
        case .text(let s, _, _): return "\(s.count) chars"
        case .delay: return ""
        case .layer(let op, let n): return "\(op.rawValue.uppercased())\(n)"
        case .repeatBlock(let count, _): return "\(count)×"
        case .raw: return ""
        }
    }
}
```

Then create `Sources/SMKConfigurator/Views/MacroStepRowView.swift` with a
`MacroStepRowView` taking `step`, `index`, `isSelected`, and closures
`onSelect`, `onMoveUp`, `onMoveDown`, `onDelete`.

Critical: `TapTarget` cannot branch internally, so the selected state is passed
as values:

```swift
        TapTarget(
            background: isSelected ? chrome.accentWash : chrome.column,
            cornerRadius: 7,
            border: isSelected ? chrome.accent : Color.white.opacity(0.05),
            action: onSelect
        ) {
            // row content
        }
```

Row anatomy, 12pt gaps, 10×13 padding: an 11pt-wide control column holding ▲▼
buttons, the index at 11pt monospace `chrome.textTertiary` (14pt wide), a 30pt
type badge, `step.payloadSummary`, a `Spacer`, `step.metadataLabel` right-aligned
at 11pt monospace, and a ✕ delete button.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --build-system native --filter MacroTests`
Expected: PASS, 12 tests.

Then: `swift build --target SMKConfigurator --build-system native` — must build.

- [ ] **Step 5: Commit**

```bash
git add Sources/SMKConfigurator/Model/Macro.swift Sources/SMKConfigurator/Views/MacroStepRowView.swift Tests/SMKConfiguratorTests/MacroTests.swift
git commit -m "Add the macro sequence row"
```

---

### Task 12: The inspector and wiring it all into ContentView

**Files:**
- Create: `Sources/SMKConfigurator/Views/MacroInspectorView.swift`
- Modify: `Sources/SMKConfigurator/Views/ContentView.swift`

**Interfaces:**
- Consumes: everything from Tasks 9–11
- Produces: `MacroInspectorView`, `MacroInspectorTab`

- [ ] **Step 1: Write the failing test**

This task is view composition; its check is the running app, not a unit test. But
the tab enum is derivable, so append to `MacroEditingTests`:

```swift
    @Test("the inspector offers three tabs in design order")
    func inspectorTabs() {
        #expect(MacroInspectorTab.allCases.map(\.label) == ["Step", "Macro", "Timing"])
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --build-system native --filter MacroEditingTests`
Expected: compile failure — `cannot find 'MacroInspectorTab' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/SMKConfigurator/Views/MacroInspectorView.swift`:

```swift
import Foundation
import SwiftCrossUI

enum MacroInspectorTab: String, CaseIterable, Identifiable, Hashable {
    case step, macro, timing

    var id: String { rawValue }

    var label: String {
        switch self {
        case .step: return "Step"
        case .macro: return "Macro"
        case .timing: return "Timing"
        }
    }
}
```

Then `MacroInspectorView`, 248pt wide, 15×14 padding, 14pt gaps:

- A three-button tab group — three separate gapped `TapTarget`s, **not** a
  segmented control, each `background: tab == selected ? chrome.accent : chrome.pillBackground`.
- The Step tab renders per-step editors using the native controls: `TextEditor`
  for text steps, `Slider` for typing speed and delay, `Picker` for the layer op
  and layer index, `ToggleSwitch` for "Repeat while held". Each writes back via
  `editor.updateMacro(_:)`.
- A Delete button for the selected step, since ⌫ isn't available.
- The Macro tab holds the name field and the bound-key summary; the Timing tab
  shows `estimatedDurationLabel` and the per-step breakdown.
- When `editor.selectedStepIndex == nil`, the Step tab shows
  "Select a step to edit it." at 12pt `chrome.textTertiary`.

In `Sources/SMKConfigurator/Views/ContentView.swift`, replace the three
`case .macros:` placeholders from Task 8:

- **listColumn** — `switch editor.macroWorkspace`: `.library` → `EmptyView()`
  (the table takes the whole body), `.editor` → `MacroStepPaletteView()`
- **mainContent** — `.library` → `MacroLibraryView()`, `.editor` →
  `MacroCanvasHeaderView()` above a `ScrollView` of `MacroStepRowView`s, then the
  add-step card reading exactly **"Add a step"**
- **inspectorColumn** — `.library` → `EmptyView()`, `.editor` → `MacroInspectorView()`

The sequence header row reads exactly **"Select a step to reorder or delete"**.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --build-system native --filter MacroEditingTests`
Expected: PASS, 18 tests.

Then the whole suite: `swift test --build-system native` — PASS.

Then run the app: `bash Scripts/run.sh`. Click the macros rail icon, create a
macro, add one of each step type, reorder with ▲▼, delete one, and return to the
library. Confirm no "ZStack will not function correctly with non-TupleView
content" warnings appear in the console — that message means a `TapTarget`
gained an internal branch.

- [ ] **Step 5: Commit**

```bash
git add Sources/SMKConfigurator/Views/MacroInspectorView.swift Sources/SMKConfigurator/Views/ContentView.swift Tests/SMKConfiguratorTests/MacroEditingTests.swift
git commit -m "Add the macro inspector and wire macros into ContentView"
```

---

### Task 13: Honest affordances for the deferred features

Contract C4: nothing in the UI may claim a capability this build lacks.

**Files:**
- Modify: `Sources/SMKConfigurator/Views/MacroEditorViews.swift`, `Sources/SMKConfigurator/Views/MacroLibraryView.swift`

**Interfaces:**
- Consumes: `MacroBudget.blockReason` from Task 5
- Produces: no new types

- [ ] **Step 1: Write the failing test**

Append to `MacroCapacityTests`:

```swift
    @Test("a budget that can't flash explains why in one sentence")
    func blockReasonIsAFullSentence() {
        let budget = MacroBudget(capacity: MacroCapacity(macroBytes: 0, macroSlots: 0),
                                 source: .device, macros: [])
        let reason = budget.blockReason
        #expect(reason?.hasSuffix(".") == true)
        #expect(reason?.isEmpty == false)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --build-system native --filter MacroCapacityTests`
Expected: PASS already (the reason strings from Task 5 end in periods). If it
fails, fix the strings in `MacroCapacity.swift` rather than the test.

- [ ] **Step 3: Write minimal implementation**

In `MacroStepPaletteView`, render "Record from board" with `.disabled(true)` and
the helper line beneath it reading exactly:

```
Recording from the board isn't available yet.
```

Replace the design's "Captured events append as steps and keep their measured
gaps." — that describes behaviour this build does not have.

In `MacroLibraryView`, disable "Record new" the same way.

Wire the "Test run" button to walk the open macro's steps and write a trace into
the inspector's Timing tab using `estimatedDurationMs`. Under the trace, add at
11pt `chrome.textTertiary`:

```
Test run estimates timing only. It doesn't send keystrokes.
```

Where `editor.macroBudget.canFlash` is false, show `blockReason` at 11pt
`chrome.dangerText` beneath the SLOT meter.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --build-system native`
Expected: PASS.

Then `bash Scripts/run.sh` and confirm the disabled buttons read as disabled and
their reasons are visible.

- [ ] **Step 5: Commit**

```bash
git add Sources/SMKConfigurator/Views/MacroEditorViews.swift Sources/SMKConfigurator/Views/MacroLibraryView.swift Tests/SMKConfiguratorTests/MacroCapacityTests.swift
git commit -m "Say plainly which macro features aren't built yet"
```

---

### Task 14: Saved macros become placeable keys

The payoff: a saved macro appears in the KEY-mode palette drawer and drops onto a
key like any other token.

**Files:**
- Modify: `Sources/SMKConfigurator/Views/PaletteDrawerView.swift`, `Sources/SMKConfigurator/Views/KeyCapView.swift`
- Test: `Tests/SMKConfiguratorTests/MacroEditingTests.swift`

**Interfaces:**
- Consumes: `ActionToken.macro(Int)`, `EditorState.macroName(for:)`
- Produces: `PaletteDrawerView.macroSectionHeight`, `PaletteDrawerView.macroTokens(for:)`

- [ ] **Step 1: Write the failing test**

Append to the `MacroEditingTests` suite:

```swift
    @Test("the palette offers one macro token per saved macro")
    func paletteListsMacros() {
        var doc = KeymapDocument(
            matrix: .init(rows: [0], cols: [1], colsAreDriven: 1),
            layers: [[["none"]]]
        )
        doc.macros = [
            MacroDefinition(id: 0, name: "a", steps: []),
            MacroDefinition(id: 4, name: "b", steps: []),
        ]
        #expect(PaletteDrawerView.macroTokens(for: doc) == [.macro(0), .macro(4)])
    }

    @Test("the MACROS section height doesn't grow with the macro count")
    func macroSectionHeightIsFixed() {
        // PaletteDrawerView's height math is static and feeds
        // ContentView.minWindowHeight. If this section grew with the
        // document, the window's minimum height would depend on how many
        // macros the user owns.
        var few = KeymapDocument(
            matrix: .init(rows: [0], cols: [1], colsAreDriven: 1),
            layers: [[["none"]]]
        )
        few.macros = [MacroDefinition(id: 0, name: "a", steps: [])]

        var many = few
        many.macros = (0..<40).map { MacroDefinition(id: $0, name: "m\($0)", steps: []) }

        // The height is a `static let` taking no document, so it cannot vary
        // with content — this asserts it exists and is sane, while the token
        // counts below confirm the content really does vary.
        #expect(PaletteDrawerView.macroSectionHeight > 0)
        #expect(PaletteDrawerView.macroTokens(for: many).count == 40)
        #expect(PaletteDrawerView.macroTokens(for: few).count == 1)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --build-system native --filter MacroEditingTests`
Expected: compile failure — `type 'PaletteDrawerView' has no member 'macroTokens'`.

- [ ] **Step 3: Write minimal implementation**

In `Sources/SMKConfigurator/Views/PaletteDrawerView.swift`, add:

```swift
    /// One chip per saved macro, in slot order.
    static func macroTokens(for document: KeymapDocument) -> [ActionToken] {
        document.macroList.sorted { $0.id < $1.id }.map { .macro($0.id) }
    }

    /// The MACROS section is deliberately fixed at one horizontally-scrolling
    /// row no matter how many macros exist. `maxHeight` and
    /// `idealContentHeight` here are static and feed
    /// `ContentView.minWindowHeight`; a section that grew with the document
    /// would make the window's minimum height depend on how many macros the
    /// user happens to own.
    static let macroSectionHeight: Double = sectionHeight(rows: 1)
```

Render the section after the generated key groups, before "Layers & Special",
titled `MACROS`, using the same chip view the other sections use so tapping a
chip assigns the token exactly as an ordinary key does. When the document has no
macros, render the section header with a 11pt `chrome.textTertiary` line
"No macros yet." rather than omitting the section — a section that appears and
disappears would change the drawer's height, which is the thing this must not do.

Add `macroSectionHeight` to whichever total the file computes (`idealContentHeight`
or equivalent) so the drawer accounts for the new row. Read the existing height
math first and follow it exactly.

In `Sources/SMKConfigurator/Views/KeyCapView.swift`, give the view an optional
name resolver so a macro keycap can show its name:

```swift
    /// Resolves `macro:<id>` to the macro's name. Every other token's
    /// `displayLabel` is self-sufficient; this one needs the document.
    var macroName: ((Int) -> String?)? = nil
```

Where the label is computed, prefer the resolved name when the token is
`.macro(n)` and a resolver is supplied, falling back to `token.displayLabel`
("M5") otherwise. Pass `editor.macroName(for:)` from the board view.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --build-system native --filter MacroEditingTests`
Expected: PASS, 20 tests.

Then the whole suite: `swift test --build-system native` — PASS.

Then `bash Scripts/run.sh`: create a macro named "Build & deploy", return to the
library, switch to the KEY rail, find the MACROS palette section, tap its chip
onto a key, and confirm the keycap shows the macro's name. Resize the window to
its minimum and confirm the palette drawer still lays out correctly with 0, 1,
and many macros.

- [ ] **Step 5: Commit**

```bash
git add Sources/SMKConfigurator/Views/PaletteDrawerView.swift Sources/SMKConfigurator/Views/KeyCapView.swift Tests/SMKConfiguratorTests/MacroEditingTests.swift
git commit -m "Place saved macros on keys from the palette drawer"
```

---

### Task 15: Document the coupling

The repo records every firmware coupling in `CLAUDE.md`. Macros add three, and
sub-project 3 will be written by someone reading that file.

**Files:**
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: everything
- Produces: no code

- [ ] **Step 1: Write the failing test**

No test — this is documentation. Verify by reading.

- [ ] **Step 2: Confirm what needs recording**

Run `git log --oneline main..HEAD` and confirm Tasks 1–14 are all present.

- [ ] **Step 3: Write the documentation**

In `CLAUDE.md`, under "Firmware coupling", add:

```markdown
- **Macros** (`Model/Macro.swift`) are carried in `keymap.json` under an
  optional top-level `"macros"` array and uploaded with the layers. Three
  things must stay in lockstep with the firmware, and none of them exists on
  the firmware side yet (see
  `docs/superpowers/specs/2026-08-20-macro-creation-design.md`, sub-project 3):
  the `macro:N` action token in `ActionToken`/`KeyAction`; the step schema
  parsed from `"macros"`; and `MacroStep.compiledSize`'s byte widths, which
  are the contract behind the editor's byte meter — if the firmware's player
  uses different widths, the meter lies.
- `MacroCapacity.floor` is what the editor assumes before any board has
  reported its real capacity via the (not yet implemented) `CAPS` command.
  It is a deliberate under-promise, not a target.
```

Under "Architecture", extend the `RailMode` paragraph to note that `.macros` is
the one mode with sub-states (`MacroWorkspace`), and why.

- [ ] **Step 4: Verify**

Read the edited sections back and confirm they match what the code actually does.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md
git commit -m "Document the macro firmware coupling"
```

---

## Out of scope

These belong to later sub-projects and must not be attempted here:

- The firmware side — `macro:N` in `KeyAction`, the macro parser, the bytecode
  player, per-port capacity, the `CAPS` command, the `SMK_KEYMAP_MAX_LEN` and
  partition change (sub-project 3)
- Recording from the board (sub-project 4)
- The flow view, node graph, and condition steps (sub-project 5)
- The macOS helper daemon (out of the program by decision)
