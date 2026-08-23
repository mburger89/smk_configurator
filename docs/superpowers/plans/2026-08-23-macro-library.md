# Macro Library Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the macro library from a flat open/delete table into a workable
one — search, collections, per-macro enable/disable, duplicate, and
round-trippable per-macro export/import.

**Architecture:** Two new `MacroDefinition` fields (`enabled`, `collection`)
ride in `keymap.json` and are invisible to the firmware. `enabled` is
load-bearing in the compiler: a disabled macro is omitted from the uploaded
payload and every cell bound to it compiles as `none`, so disabling frees
real bytes against the shared macro/layer budget. Everything else — search,
collection filtering, duplicate, export/import — is editor-only, built as
pure model functions with the views doing nothing but binding to them.

**Tech Stack:** Swift 6, SwiftCrossUI, Swift Testing (`@Suite` structs),
`JSONEncoder`/`JSONDecoder` with hand-written `Codable` conformances.

**Spec:** `docs/superpowers/specs/2026-08-22-macro-library-design.md`

## Global Constraints

- **Build:** `swift build --target SMKConfigurator --build-system native`.
  Never a bare `swift build` — it compiles swift-cross-ui's Windows-only
  backend and fails. Both flags are required; see `CLAUDE.md`.
- **Test:** `swift test --build-system native`, or one suite with
  `--filter <SuiteName>`.
- **The firmware never sees `enabled` or `collection`.** They exist only in
  `keymap.json` on disk. The binary payload (`compileKeymap`) carries no such
  fields, so `Sources/SMKCore/KeymapBinary.swift` and
  `generate_default_keymap.sh` in `~/esp/SMK` need **no** change from this
  plan. If you find yourself editing the firmware repo, stop — you have
  misread a task.
- **Saving stays lossless.** Unknown per-macro fields round-trip
  (`MacroDefinition.unknownFields`), and so must a *known* field carrying a
  mistyped value. Never coerce `{"enabled": "yes"}` into `true` and write
  `true` back.
- **Both new fields encode only when non-default** — `enabled` only when
  `false`, `collection` only when non-nil. An existing `keymap.json` that is
  opened and saved must not gain keys it never had. This mirrors
  `KeymapDocument.macros` being optional for exactly the same reason.
- **SwiftCrossUI has no drag and no keyboard shortcuts.** Only
  `onTapGesture`, `onHover`, `onChange`, `onSubmit`, `onOpenURL`.
- **Tap targets do not nest, and `.onHover` must be chained onto the same
  view as `.onTapGesture`.** A `ZStack` acting as a tap target must have
  exactly two direct children, neither produced by an `if`. See the doc
  comment on `MacroLibraryRowView` in `Views/MacroLibraryView.swift` — it
  records the bug that taught this.
- **Commit after every task**, message in the imperative mood, no trailing
  "Generated with" footer unless the repo's recent history shows one.

---

## File Structure

Nothing new is created except one test file per concern. The work lands in
files that already own the responsibility:

| File | Change |
|---|---|
| `Sources/SMKConfigurator/Model/Macro.swift` | `enabled`/`collection` on `MacroDefinition`, their codec, `MacroStep.searchableText` |
| `Sources/SMKConfigurator/Model/KeymapDocument.swift` | `macroCollections` derivation |
| `Sources/SMKConfigurator/Model/KeymapCompiler.swift` | skip disabled macros; compile their bound cells as `none` |
| `Sources/SMKConfigurator/Model/MacroCapacity.swift` | `MacroBudget` counts only enabled macros |
| `Sources/SMKConfigurator/Model/EditorState.swift` | `setMacroEnabled`, `setMacroCollection`, `duplicateMacro`, `importMacro`, `exportMacro` |
| `Sources/SMKConfigurator/Views/MacroLibraryView.swift` | row controls, search field, collection filter, import/export buttons, `MacroLibraryFilter` |
| `Tests/SMKConfiguratorTests/MacroTests.swift` | codec tests (Task 1) |
| `Tests/SMKConfiguratorTests/KeymapCompilerTests.swift` | disabled-macro compile tests (Task 2) |
| `Tests/SMKConfiguratorTests/MacroCapacityTests.swift` | budget tests (Task 3) |
| `Tests/SMKConfiguratorTests/MacroEditingTests.swift` | `EditorState` mutator tests (Tasks 4–6) |
| `Tests/SMKConfiguratorTests/MacroLibraryFilterTests.swift` | **create** — filtering (Task 8) |

`MacroLibraryView.swift` is 266 lines and gains a header, a filter type and
three row controls. If it passes ~450 lines, split the row view into
`Views/MacroLibraryRowView.swift` — but do it as part of the task that
crosses the line, not as a separate cleanup commit.

---

### Task 1: `enabled` and `collection` on `MacroDefinition`

**Files:**
- Modify: `Sources/SMKConfigurator/Model/Macro.swift:270-315` (the
  `MacroDefinition` struct, its `init`, `CodingKeys`, `init(from:)` and
  `encode(to:)`)
- Test: `Tests/SMKConfiguratorTests/MacroTests.swift`

**Interfaces:**
- Consumes: nothing from other tasks — this is the root.
- Produces:
  - `MacroDefinition.enabled: Bool` (default `true`)
  - `MacroDefinition.collection: String?` (default `nil`)
  - `init(id: Int, name: String, steps: [MacroStep], enabled: Bool = true, collection: String? = nil)`
    — the defaults are mandatory; roughly 40 existing call sites in tests and
    `EditorState.createMacro()` use the three-argument form and must keep
    compiling untouched.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/SMKConfiguratorTests/MacroTests.swift`, inside the existing
suite that covers `MacroDefinition` decoding (match the surrounding
`@Test("...")` naming style):

```swift
@Test("a macro with no enabled field decodes as enabled")
func missingEnabledMeansEnabled() throws {
    let json = #"{"id":0,"name":"M","steps":[]}"#
    let macro = try JSONDecoder().decode(MacroDefinition.self, from: Data(json.utf8))
    #expect(macro.enabled)
    #expect(macro.collection == nil)
}

@Test("enabled and collection round-trip")
func enabledAndCollectionRoundTrip() throws {
    var macro = MacroDefinition(id: 3, name: "M", steps: [])
    macro.enabled = false
    macro.collection = "Work"
    let data = try JSONEncoder().encode(macro)
    let back = try JSONDecoder().decode(MacroDefinition.self, from: data)
    #expect(back == macro)
}

@Test("defaults are omitted so an existing file gains no keys")
func defaultsAreOmitted() throws {
    let macro = MacroDefinition(id: 0, name: "M", steps: [])
    let text = String(decoding: try JSONEncoder().encode(macro), as: UTF8.self)
    #expect(!text.contains("enabled"))
    #expect(!text.contains("collection"))
}

@Test("a mistyped enabled value is preserved rather than coerced")
func mistypedEnabledIsPreserved() throws {
    let json = #"{"id":0,"name":"M","steps":[],"enabled":"yes"}"#
    let macro = try JSONDecoder().decode(MacroDefinition.self, from: Data(json.utf8))
    // Treated as enabled -- the safe reading -- but the original value is
    // still in the file after a save.
    #expect(macro.enabled)
    let text = String(decoding: try JSONEncoder().encode(macro), as: UTF8.self)
    #expect(text.contains("\"enabled\":\"yes\""))
}

@Test("a mistyped value doesn't produce a duplicate key once really set")
func mistypedValueIsReplacedWhenSet() throws {
    let json = #"{"id":0,"name":"M","steps":[],"enabled":"yes"}"#
    var macro = try JSONDecoder().decode(MacroDefinition.self, from: Data(json.utf8))
    macro.enabled = false
    let data = try JSONEncoder().encode(macro)
    // Decodes cleanly, which it could not if "enabled" appeared twice
    // with conflicting types.
    let back = try JSONDecoder().decode(MacroDefinition.self, from: data)
    #expect(back.enabled == false)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --build-system native --filter MacroTests`
Expected: FAIL — `value of type 'MacroDefinition' has no member 'enabled'`.

- [ ] **Step 3: Write the implementation**

In `Sources/SMKConfigurator/Model/Macro.swift`, replace the
`MacroDefinition` stored properties, `init`, `CodingKeys`, `init(from:)`
and `encode(to:)` with:

```swift
    var id: Int
    var name: String
    var steps: [MacroStep]

    /// Whether this macro is compiled into the payload uploaded to a board.
    /// A disabled macro stays in `keymap.json` in full, but `compileKeymap`
    /// omits it and compiles every cell bound to it as `none` -- so
    /// disabling frees real bytes against the budget macros share with
    /// layers, which is the main reason to want it. Re-enabling restores
    /// the key with no re-binding, because the `macro:<id>` token was never
    /// removed from the document.
    ///
    /// Defaults to `true` and is only *encoded* when false: every macro
    /// written before this field existed must keep loading as enabled, and
    /// opening and saving such a file must not add a key to it.
    var enabled: Bool = true

    /// An optional grouping label for the library, `nil` meaning ungrouped.
    /// Purely an editor concept -- the firmware never sees it.
    ///
    /// Lives on the macro rather than in an editor-side store keyed by id,
    /// which would be actively wrong: `KeymapDocument.nextMacroID` hands out
    /// the lowest free slot, so deleting macro 0 and creating another gives
    /// the new macro id 0, and any side store would silently re-attribute
    /// the deleted macro's collection to its replacement.
    var collection: String? = nil

    /// Any per-macro field this build doesn't have a model property for --
    /// e.g. a future build's "repeatWhileHeld" flag -- plus any *known*
    /// field whose value had the wrong type to decode (see `init(from:)`).
    /// Carried through unchanged on save, same lossless principle as
    /// `MacroStep.raw`: this build not understanding something must not
    /// mean it gets to delete it.
    private var unknownFields: [String: JSONValue] = [:]

    init(id: Int, name: String, steps: [MacroStep],
         enabled: Bool = true, collection: String? = nil) {
        self.id = id
        self.name = name
        self.steps = steps
        self.enabled = enabled
        self.collection = collection
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, steps, enabled, collection
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        steps = try c.decode([MacroStep].self, forKey: .steps)

        // A *known* key whose value has the wrong type is preserved
        // verbatim rather than coerced, exactly as an unknown step becomes
        // `MacroStep.raw`: `{"enabled": "yes"}` was written by something,
        // and silently rewriting it to `true` destroys the only evidence of
        // what that something meant. The macro reads as its default in this
        // build; `encode(to:)` puts the original value back.
        var malformed: [String] = []
        if let decoded = try? c.decodeIfPresent(Bool.self, forKey: .enabled) {
            enabled = decoded ?? true
        } else {
            enabled = true
            malformed.append(CodingKeys.enabled.stringValue)
        }
        if let decoded = try? c.decodeIfPresent(String.self, forKey: .collection) {
            collection = decoded
        } else {
            collection = nil
            malformed.append(CodingKeys.collection.stringValue)
        }

        let dynamic = try decoder.container(keyedBy: DynamicCodingKey.self)
        for key in dynamic.allKeys
        where CodingKeys(stringValue: key.stringValue) == nil
            || malformed.contains(key.stringValue) {
            unknownFields[key.stringValue] = try dynamic.decode(JSONValue.self, forKey: key)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(steps, forKey: .steps)
        // Non-default only: an existing file must not gain keys merely from
        // being opened and saved.
        if !enabled { try c.encode(false, forKey: .enabled) }
        if let collection { try c.encode(collection, forKey: .collection) }

        var dynamic = encoder.container(keyedBy: DynamicCodingKey.self)
        for (key, value) in unknownFields {
            // A preserved malformed value and a real one would otherwise
            // both be written, leaving the same key twice in one object.
            // The real value wins: the user set it in this build.
            if key == CodingKeys.enabled.stringValue && !enabled { continue }
            if key == CodingKeys.collection.stringValue && collection != nil { continue }
            guard let codingKey = DynamicCodingKey(stringValue: key) else { continue }
            try dynamic.encode(value, forKey: codingKey)
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --build-system native`
Expected: PASS — the whole suite, not just `MacroTests`. Adding stored
properties changes `Equatable`/`Hashable` synthesis, so a test elsewhere
comparing macros could legitimately break; if one does, it is telling you
something real. Fix the cause, not the assertion.

- [ ] **Step 5: Commit**

```bash
git add Sources/SMKConfigurator/Model/Macro.swift Tests/SMKConfiguratorTests/MacroTests.swift
git commit -m "Add enabled and collection to MacroDefinition"
```

---

### Task 2: The compiler skips disabled macros and deadens their keys

**Files:**
- Modify: `Sources/SMKConfigurator/Model/KeymapCompiler.swift:366-412`
  (`compileKeymap`)
- Test: `Tests/SMKConfiguratorTests/KeymapCompilerTests.swift`

**Interfaces:**
- Consumes: `MacroDefinition.enabled` (Task 1).
- Produces: no new API. A behavioural change to `compileKeymap(_:)`, whose
  signature stays `func compileKeymap(_ document: KeymapDocument) throws -> [UInt8]`.

**Why the bound cell becomes `none` rather than staying `macro:N`:** the
firmware's decoder was frozen and flashed before this feature existed. It has
no tolerance for a `macro:` cell naming a slot that isn't in the payload, and
teaching it some would mean a contract change across two repos for an
editor-side convenience. `none` is a dead key the decoder already
understands. The binding is untouched in `keymap.json`, so re-enabling
restores it.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/SMKConfiguratorTests/KeymapCompilerTests.swift`:

```swift
@Test("a disabled macro contributes no bytes and isn't counted")
func disabledMacroContributesNothing() throws {
    let steps: [MacroStep] = [.delay(ms: 10)]
    let enabled = MacroDefinition(id: 0, name: "A", steps: steps)
    var disabled = MacroDefinition(id: 1, name: "B", steps: steps)
    disabled.enabled = false

    let doc = KeymapDocument(
        matrix: .init(rows: [0], cols: [1], colsAreDriven: 1),
        layers: [[["none"]]],
        macros: [enabled, disabled])
    let onlyEnabled = KeymapDocument(
        matrix: .init(rows: [0], cols: [1], colsAreDriven: 1),
        layers: [[["none"]]],
        macros: [enabled])

    #expect(try compileKeymap(doc) == (try compileKeymap(onlyEnabled)))
    // The header's macroCount is byte 4.
    #expect(try compileKeymap(doc)[4] == 1)
}

@Test("a cell bound to a disabled macro compiles as none")
func disabledMacroKeyCompilesAsNone() throws {
    var disabled = MacroDefinition(id: 2, name: "B", steps: [])
    disabled.enabled = false
    let doc = KeymapDocument(
        matrix: .init(rows: [0], cols: [1], colsAreDriven: 1),
        layers: [[["macro:2"]]],
        macros: [disabled])

    let bytes = try compileKeymap(doc)
    // 6-byte header + 1 row GPIO + 1 col GPIO = the cell starts at index 8.
    let (noneTag, noneParam) = try encodeCell(.none)
    #expect(bytes[8] == noneTag)
    #expect(bytes[9] == noneParam)
}

@Test("a cell bound to an enabled macro still compiles as that macro")
func enabledMacroKeyStillCompiles() throws {
    let doc = KeymapDocument(
        matrix: .init(rows: [0], cols: [1], colsAreDriven: 1),
        layers: [[["macro:2"]]],
        macros: [MacroDefinition(id: 2, name: "B", steps: [])])

    let bytes = try compileKeymap(doc)
    let (tag, param) = try encodeCell(.macro(2))
    #expect(bytes[8] == tag)
    #expect(bytes[9] == param)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --build-system native --filter KeymapCompilerTests`
Expected: FAIL — the disabled macro's bytes are still in the payload, so the
two compiles differ and `macroCount` reads 2.

- [ ] **Step 3: Write the implementation**

In `compileKeymap`, replace the `let macros = document.macroList` line with:

```swift
    // A disabled macro is omitted from the payload entirely, and every cell
    // bound to it compiles as a dead key below -- see the plan/spec for why
    // `none` rather than a dangling `macro:` reference the frozen firmware
    // decoder would have to tolerate.
    let macros = document.macroList.filter(\.enabled)
    let disabledMacroIDs = Set(document.macroList.lazy.filter { !$0.enabled }.map(\.id))
```

and replace the cell loop's body with:

```swift
            for (colIndex, cellString) in row.enumerated() {
                let token = ActionToken.parse(cellString)
                // The cell keeps its `macro:N` string in `keymap.json`;
                // only what reaches the board changes, so re-enabling the
                // macro brings the key back with no re-binding.
                var effective = token
                if case .macro(let slot) = token, disabledMacroIDs.contains(slot) {
                    effective = .none
                }
                do {
                    let (tag, param) = try encodeCell(effective)
                    bytes.append(tag)
                    bytes.append(param)
                } catch let underlying as KeymapCompileError {
                    // Names the token the user actually wrote, not the
                    // substitution.
                    throw KeymapCompileError.invalidCell(
                        layer: layerIndex, row: rowIndex, col: colIndex,
                        token: token.canonicalString, reason: underlying.description)
                }
            }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --build-system native`
Expected: PASS, including `BinaryFormatAgreementTests` — the reference
`keymap.json` has no disabled macros, so its compiled bytes must be
unchanged. If that suite fails, the filter is wrong, not the fixture.

- [ ] **Step 5: Commit**

```bash
git add Sources/SMKConfigurator/Model/KeymapCompiler.swift Tests/SMKConfiguratorTests/KeymapCompilerTests.swift
git commit -m "Omit disabled macros from the payload and deaden their keys"
```

---

### Task 3: `MacroBudget` counts only enabled macros

**Files:**
- Modify: `Sources/SMKConfigurator/Model/MacroCapacity.swift:76-81` (the
  `macros:` initializer)
- Test: `Tests/SMKConfiguratorTests/MacroCapacityTests.swift`

**Interfaces:**
- Consumes: `MacroDefinition.enabled` (Task 1), `compileKeymap` skipping
  disabled macros (Task 2).
- Produces: no new API. `MacroBudget.usedSlots` and `usedBytes` now exclude
  disabled macros.

Disabling is only worth doing if it frees the budget — macros and layers
share one, so this is the whole point of the feature rather than a detail.

- [ ] **Step 1: Write the failing test**

Append to `Tests/SMKConfiguratorTests/MacroCapacityTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --build-system native --filter MacroCapacityTests`
Expected: FAIL — `usedSlots` is 2 and `usedBytes` counts both macros.

- [ ] **Step 3: Write the implementation**

Replace the `macros:` initializer's body in `MacroCapacity.swift`:

```swift
    init(capacity: MacroCapacity, source: MacroCapacitySource, macros: [MacroDefinition], layerBytes: Int = 0) {
        // Disabled macros are omitted from the payload by `compileKeymap`,
        // so counting them here would report a cost the board never pays --
        // and since macros share one budget with layers, "disable a macro to
        // fit" has to actually free bytes or the feature is theatre.
        let counted = macros.filter(\.enabled)
        self.capacity = capacity
        self.source = source
        self.usedSlots = counted.count
        self.layerBytes = layerBytes
        self.layerCostUnknown = false
        (self.usedBytes, self.usedBytesIsEstimated) = Self.compiledMacroBytes(counted)
    }
```

`init(capacity:source:document:)` needs no change: it forwards
`document.macroList` to this initializer, and its `layerBytes` probe strips
macros entirely. Cells stay two bytes each whether or not they compile to
`none`, so a disabled binding doesn't move `layerBytes` either.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --build-system native`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SMKConfigurator/Model/MacroCapacity.swift Tests/SMKConfiguratorTests/MacroCapacityTests.swift
git commit -m "Exclude disabled macros from the macro budget"
```

---

### Task 4: Enable/disable and collection assignment on `EditorState`

**Files:**
- Modify: `Sources/SMKConfigurator/Model/KeymapDocument.swift` (add
  `macroCollections`, next to `nextMacroID` around line 36)
- Modify: `Sources/SMKConfigurator/Model/EditorState.swift` (add to the
  "MARK: - Macro editing" section, after `updateMacro(_:)` around line 810)
- Test: `Tests/SMKConfiguratorTests/MacroEditingTests.swift`

**Interfaces:**
- Consumes: `MacroDefinition.enabled`/`collection` (Task 1),
  `EditorState.updateMacro(_:)` (existing).
- Produces:
  - `KeymapDocument.macroCollections: [String]` — sorted, de-duplicated,
    derived from macros
  - `EditorState.setMacroEnabled(id: Int, _ enabled: Bool)`
  - `EditorState.setMacroCollection(id: Int, _ collection: String?)`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/SMKConfiguratorTests/MacroEditingTests.swift` (the suite is
`@MainActor`; its `editor()` helper is already defined at the top of the file):

```swift
@Test("disabling a macro marks the document dirty and keeps the macro")
func disableKeepsMacro() {
    let e = editor()
    e.createMacro()
    e.isDirty = false
    e.setMacroEnabled(id: 0, false)
    #expect(e.document.macroList.count == 1)
    #expect(e.document.macroList[0].enabled == false)
    #expect(e.isDirty)
}

@Test("assigning a collection stores it, and clearing it stores nil")
func collectionAssignment() {
    let e = editor()
    e.createMacro()
    e.setMacroCollection(id: 0, "Work")
    #expect(e.document.macroList[0].collection == "Work")
    e.setMacroCollection(id: 0, nil)
    #expect(e.document.macroList[0].collection == nil)
}

@Test("a blank or whitespace collection reads as ungrouped")
func blankCollectionIsNil() {
    let e = editor()
    e.createMacro()
    e.setMacroCollection(id: 0, "   ")
    #expect(e.document.macroList[0].collection == nil)
}

@Test("collections derive from macros, so emptying one removes it")
func collectionsDerive() {
    let e = editor()
    e.createMacro()                       // id 0
    e.createMacro()                       // id 1
    e.setMacroCollection(id: 0, "Work")
    e.setMacroCollection(id: 1, "Play")
    #expect(e.document.macroCollections == ["Play", "Work"])
    e.setMacroCollection(id: 1, nil)
    #expect(e.document.macroCollections == ["Work"])
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --build-system native --filter MacroEditingTests`
Expected: FAIL — `value of type 'EditorState' has no member 'setMacroEnabled'`.

- [ ] **Step 3: Write the implementation**

In `KeymapDocument.swift`, after `nextMacroID`:

```swift
    /// Every collection name currently in use, sorted. Derived rather than
    /// stored: a collection is just a string on a macro, so emptying the
    /// last macro out of one makes it disappear on its own, with no
    /// separate list to keep in sync or garbage-collect.
    var macroCollections: [String] {
        Set(macroList.compactMap(\.collection)).sorted()
    }
```

In `EditorState.swift`, after `updateMacro(_:)`:

```swift
    /// Disabling keeps the macro and its key bindings in `keymap.json` in
    /// full -- it only stops the macro being compiled into the payload, so
    /// the bytes it was spending come back (see `compileKeymap`). Any key
    /// bound to it compiles as a dead key until it is re-enabled.
    func setMacroEnabled(id: Int, _ enabled: Bool) {
        guard var macro = document.macroList.first(where: { $0.id == id }) else { return }
        macro.enabled = enabled
        updateMacro(macro)
    }

    /// A blank or whitespace-only name reads as ungrouped rather than
    /// creating a collection whose name renders as nothing -- the picker
    /// derives its options from these strings, and an invisible option is
    /// unselectable in practice.
    func setMacroCollection(id: Int, _ collection: String?) {
        guard var macro = document.macroList.first(where: { $0.id == id }) else { return }
        let trimmed = collection?.trimmingCharacters(in: .whitespacesAndNewlines)
        macro.collection = (trimmed?.isEmpty ?? true) ? nil : trimmed
        updateMacro(macro)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --build-system native`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SMKConfigurator/Model/KeymapDocument.swift Sources/SMKConfigurator/Model/EditorState.swift Tests/SMKConfiguratorTests/MacroEditingTests.swift
git commit -m "Add enable/disable and collection assignment for macros"
```

---

### Task 5: Duplicate a macro

**Files:**
- Modify: `Sources/SMKConfigurator/Model/EditorState.swift` (macro editing
  section, after `setMacroCollection`)
- Test: `Tests/SMKConfiguratorTests/MacroEditingTests.swift`

**Interfaces:**
- Consumes: `KeymapDocument.nextMacroID` (existing), `MacroDefinition.maxID`
  (existing, 255), `EditorState.loadError` (existing `String?` used for
  user-facing failures — see `importTheme(from:)` for the precedent).
- Produces: `@discardableResult EditorState.duplicateMacro(id: Int) -> Bool`

**On the refusal condition:** refuse only when every slot `0...255` is taken
— the format's own limit. Do *not* refuse against `macroCapacity.macroSlots`:
that number is discovered from a board, may be a conservative floor guess
when no board has ever connected, and exceeding it is already reported by
`MacroBudget.blockReason` at flash time. Blocking authoring on a guess would
be the same over-promise/under-promise mistake `MacroCapacity.floor`'s doc
comment warns about, in reverse.

- [ ] **Step 1: Write the failing tests**

```swift
@Test("duplicating takes the lowest free slot and a derived name")
func duplicateTakesLowestFreeSlot() {
    let e = editor()
    e.createMacro()
    e.updateMacro(MacroDefinition(id: 0, name: "Sign off", steps: [.delay(ms: 20)]))
    #expect(e.duplicateMacro(id: 0))
    #expect(e.document.macroList.count == 2)
    let copy = e.document.macroList[1]
    #expect(copy.id == 1)
    #expect(copy.name == "Sign off copy")
    #expect(copy.steps == [.delay(ms: 20)])
}

@Test("duplicating again doesn't collide with the first copy's name")
func duplicateNamesDoNotCollide() {
    let e = editor()
    e.createMacro()
    e.updateMacro(MacroDefinition(id: 0, name: "A", steps: []))
    e.duplicateMacro(id: 0)
    e.duplicateMacro(id: 0)
    #expect(e.document.macroList.map(\.name) == ["A", "A copy", "A copy 2"])
}

@Test("duplicating refuses when every slot is taken")
func duplicateRefusesWhenFull() {
    let e = editor()
    e.document.macros = (0...MacroDefinition.maxID).map {
        MacroDefinition(id: $0, name: "M\($0)", steps: [])
    }
    #expect(e.duplicateMacro(id: 0) == false)
    #expect(e.document.macroList.count == MacroDefinition.maxID + 1)
    #expect(e.loadError != nil)
}

@Test("a duplicate carries enabled and collection across")
func duplicateCarriesFields() {
    let e = editor()
    e.createMacro()
    e.setMacroCollection(id: 0, "Work")
    e.setMacroEnabled(id: 0, false)
    e.duplicateMacro(id: 0)
    #expect(e.document.macroList[1].collection == "Work")
    #expect(e.document.macroList[1].enabled == false)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --build-system native --filter MacroEditingTests`
Expected: FAIL — no member `duplicateMacro`.

- [ ] **Step 3: Write the implementation**

```swift
    /// Copies a macro into the lowest free slot, keeping everything about it
    /// except its id and name. Returns false (and sets `loadError`) when
    /// every slot in the format's `0...MacroDefinition.maxID` range is
    /// taken, rather than silently overwriting one -- see the plan for why
    /// the board's reported slot count deliberately isn't the limit here.
    @discardableResult
    func duplicateMacro(id: Int) -> Bool {
        guard let source = document.macroList.first(where: { $0.id == id }) else { return false }
        let slot = document.nextMacroID
        guard slot <= MacroDefinition.maxID else {
            loadError = "Every macro slot (0-\(MacroDefinition.maxID)) is in use; "
                + "delete a macro before duplicating one."
            return false
        }
        var copy = source
        copy.id = slot
        copy.name = Self.copyName(for: source.name, taken: Set(document.macroList.map(\.name)))
        document.macros = document.macroList + [copy]
        isDirty = true
        return true
    }

    /// "A" -> "A copy" -> "A copy 2" -> "A copy 3". Deliberately not
    /// "A copy copy": the suffix counts copies of the original, which is
    /// what someone duplicating three times is actually producing.
    private static func copyName(for name: String, taken: Set<String>) -> String {
        let base = "\(name) copy"
        if !taken.contains(base) { return base }
        var n = 2
        while taken.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --build-system native`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SMKConfigurator/Model/EditorState.swift Tests/SMKConfiguratorTests/MacroEditingTests.swift
git commit -m "Duplicate a macro into the lowest free slot"
```

---

### Task 6: Per-macro export and import

**Files:**
- Modify: `Sources/SMKConfigurator/Model/EditorState.swift` (macro editing
  section, after `duplicateMacro`)
- Test: `Tests/SMKConfiguratorTests/MacroEditingTests.swift`

**Interfaces:**
- Consumes: `EditorState.writeJSON(_:to:errorContext:)` (existing private
  helper, `EditorState.swift:707`), `KeymapDocument.nextMacroID`.
- Produces:
  - `EditorState.exportMacro(_ macro: MacroDefinition, to url: URL)`
  - `@discardableResult EditorState.importMacro(from url: URL) -> Bool`

An imported file is untrusted — hand-edited, or from anywhere. It decodes
through the same `MacroDefinition` path as `keymap.json`, so unknown fields
and mistyped values are preserved rather than coerced (Task 1). The id in the
file is discarded and a fresh slot assigned, because that id almost certainly
collides with something already in this document.

- [ ] **Step 1: Write the failing tests**

```swift
@Test("a macro exports and imports back, keeping its steps and fields")
func exportImportRoundTrips() throws {
    let e = editor()
    e.createMacro()
    e.updateMacro(MacroDefinition(id: 0, name: "Sign off", steps: [.delay(ms: 30)],
                                  enabled: false, collection: "Work"))
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("macro-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }

    e.exportMacro(e.document.macroList[0], to: url)
    #expect(e.importMacro(from: url))

    let imported = e.document.macroList[1]
    #expect(imported.name == "Sign off")
    #expect(imported.steps == [.delay(ms: 30)])
    #expect(imported.enabled == false)
    #expect(imported.collection == "Work")
}

@Test("import assigns a fresh slot rather than the id in the file")
func importAssignsFreshSlot() throws {
    let e = editor()
    e.createMacro()   // occupies slot 0
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("macro-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let json = #"{"id":0,"name":"Imported","steps":[]}"#
    try Data(json.utf8).write(to: url)

    #expect(e.importMacro(from: url))
    #expect(e.document.macroList.map(\.id) == [0, 1])
    #expect(e.document.macroList[1].name == "Imported")
}

@Test("importing a file that isn't a macro fails and names the file")
func importRejectsNonMacro() throws {
    let e = editor()
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("not-a-macro-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data(#"{"hello":"world"}"#.utf8).write(to: url)

    #expect(e.importMacro(from: url) == false)
    #expect(e.document.macroList.isEmpty)
    #expect(e.loadError?.contains(url.lastPathComponent) == true)
}

@Test("importing refuses when every slot is taken")
func importRefusesWhenFull() throws {
    let e = editor()
    e.document.macros = (0...MacroDefinition.maxID).map {
        MacroDefinition(id: $0, name: "M\($0)", steps: [])
    }
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("macro-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data(#"{"id":0,"name":"Imported","steps":[]}"#.utf8).write(to: url)

    #expect(e.importMacro(from: url) == false)
    #expect(e.loadError != nil)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --build-system native --filter MacroEditingTests`
Expected: FAIL — no member `exportMacro`.

- [ ] **Step 3: Write the implementation**

```swift
    /// One macro per file, so a single macro can be shared. A whole-library
    /// file couldn't, and would replace rather than merge on the way back in.
    func exportMacro(_ macro: MacroDefinition, to url: URL) {
        _ = writeJSON(macro, to: url, errorContext: "export macro \"\(macro.name)\"")
    }

    /// Imports one exported macro into the lowest free slot. The id in the
    /// file is ignored: it is the slot the macro happened to occupy in the
    /// document it came from, and almost certainly collides here.
    ///
    /// Decodes through the same `MacroDefinition` path as `keymap.json`, so
    /// a file carrying fields this build doesn't know -- or a known field
    /// with a mistyped value -- is preserved rather than coerced or
    /// rejected. What it will not accept is a file that isn't a macro at
    /// all; that fails with a message naming the file.
    @discardableResult
    func importMacro(from url: URL) -> Bool {
        let slot = document.nextMacroID
        guard slot <= MacroDefinition.maxID else {
            loadError = "Every macro slot (0-\(MacroDefinition.maxID)) is in use; "
                + "delete a macro before importing one."
            return false
        }
        do {
            let data = try Data(contentsOf: url)
            var macro = try JSONDecoder().decode(MacroDefinition.self, from: data)
            macro.id = slot
            document.macros = document.macroList + [macro]
            isDirty = true
            return true
        } catch {
            loadError = "Couldn't import a macro from \(url.lastPathComponent): "
                + error.localizedDescription
            return false
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --build-system native`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SMKConfigurator/Model/EditorState.swift Tests/SMKConfiguratorTests/MacroEditingTests.swift
git commit -m "Export and import a single macro"
```

---

### Task 7: Row model and row controls

**Files:**
- Modify: `Sources/SMKConfigurator/Views/MacroLibraryView.swift` (both
  `MacroLibraryRow` and `MacroLibraryRowView`)
- Test: `Tests/SMKConfiguratorTests/MacroLibraryFilterTests.swift` (**create**
  — it covers row derivation in this task and filtering in Task 8)

**Interfaces:**
- Consumes: `MacroDefinition.enabled`/`collection` (Task 1),
  `setMacroEnabled`/`setMacroCollection` (Task 4), `duplicateMacro` (Task 5),
  `exportMacro` (Task 6).
- Produces: `MacroLibraryRow` gains
  `isEnabled: Bool`, `collection: String?`, `searchText: String`,
  `disabledWarning: String?`, and `MacroStep.searchableText: String`.

**On where Export lives.** The spec calls export and import "header
actions". Import is: there is nothing to select, and it acts on the library
as a whole. Export is not — it exports *one* macro, and the library table has
no selection concept to name which. It therefore sits on the row alongside
duplicate and delete, and only import goes in the header. Recorded as a
deliberate departure from the spec's sentence, not an oversight.

**On dropping the hover-reveal.** The delete glyph is currently revealed on
hover. With five controls on a row, hover-revealing one of them is
inconsistent, and `isHovered` cannot be shared across sibling views without
putting hover on a different view from the tap gesture — the exact bug
`MacroLibraryRowView`'s doc comment records. All controls become permanently
visible. Deletion is still confirmed by an alert, so nothing gets easier to
do by accident.

- [ ] **Step 1: Write the failing tests**

Create `Tests/SMKConfiguratorTests/MacroLibraryFilterTests.swift`:

```swift
import Testing
@testable import SMKConfigurator

@Suite("Macro library rows")
struct MacroLibraryRowTests {
    private func document(macros: [MacroDefinition], cell: String = "none") -> KeymapDocument {
        KeymapDocument(
            matrix: .init(rows: [0], cols: [1], colsAreDriven: 1),
            layers: [[[cell]]],
            macros: macros)
    }

    @Test("a row carries the macro's enabled flag and collection")
    func rowCarriesFields() {
        let macro = MacroDefinition(id: 0, name: "A", steps: [],
                                    enabled: false, collection: "Work")
        let row = MacroLibraryRow(macro: macro, document: document(macros: [macro]))
        #expect(row.isEnabled == false)
        #expect(row.collection == "Work")
    }

    @Test("a disabled but bound macro warns and names the key")
    func disabledBoundMacroWarns() throws {
        let macro = MacroDefinition(id: 0, name: "A", steps: [], enabled: false)
        let row = MacroLibraryRow(macro: macro,
                                  document: document(macros: [macro], cell: "macro:0"))
        let warning = try #require(row.disabledWarning)
        #expect(warning.contains("R0C0"))
        #expect(warning.contains("Layer 0"))
    }

    @Test("a disabled unbound macro has nothing to warn about")
    func disabledUnboundMacroIsQuiet() {
        let macro = MacroDefinition(id: 0, name: "A", steps: [], enabled: false)
        #expect(MacroLibraryRow(macro: macro, document: document(macros: [macro]))
            .disabledWarning == nil)
    }

    @Test("an enabled bound macro has nothing to warn about")
    func enabledBoundMacroIsQuiet() {
        let macro = MacroDefinition(id: 0, name: "A", steps: [])
        #expect(MacroLibraryRow(macro: macro,
                                document: document(macros: [macro], cell: "macro:0"))
            .disabledWarning == nil)
    }

    @Test("search text covers the name and every step, including nested ones")
    func searchTextCoversSteps() {
        let macro = MacroDefinition(id: 0, name: "Sign off", steps: [
            .repeatBlock(count: 2, steps: [
                .text("regards", delivery: .keystrokes, msPerChar: 10)
            ])
        ])
        let text = MacroLibraryRow(macro: macro, document: document(macros: [macro])).searchText
        #expect(text.contains("Sign off"))
        #expect(text.contains("regards"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --build-system native --filter MacroLibraryRowTests`
Expected: FAIL — `MacroLibraryRow` has no member `isEnabled`.

- [ ] **Step 3: Write the implementation**

In `Sources/SMKConfigurator/Model/Macro.swift`, alongside `payloadSummary`
and `metadataLabel` in the "Row display" section:

```swift
    /// Everything about this step the library's search should match on.
    /// Recurses into a `.repeatBlock`'s body: its own `payloadSummary` is
    /// "Repeat 2 steps 3 times", which says nothing about what those steps
    /// contain, and text buried in a repeat is exactly the kind of thing
    /// someone searches for.
    var searchableText: String {
        switch self {
        case .repeatBlock(_, let steps):
            return ([payloadSummary] + steps.map(\.searchableText)).joined(separator: " ")
        default:
            return "\(payloadSummary) \(metadataLabel)"
        }
    }
```

In `MacroLibraryView.swift`, extend `MacroLibraryRow` with the new stored
properties and set them in its initializer. The bound-key search already runs
there and produces `found`; reuse it rather than repeating the scan:

```swift
    var isEnabled: Bool
    var collection: String?
    /// Name plus every step's text, lowercased once at construction so the
    /// filter doesn't re-lowercase it per keystroke.
    var searchText: String
    /// Set only when a disabled macro still has a key bound to it -- that
    /// key compiles as a dead key (`compileKeymap` rewrites it), which is
    /// silent and easy to miss, so the row names it.
    var disabledWarning: String?
```

and, at the end of `init(macro:document:)`:

```swift
        self.isEnabled = macro.enabled
        self.collection = macro.collection
        self.searchText = ([macro.name] + macro.steps.map(\.searchableText))
            .joined(separator: " ")
            .lowercased()
        if !macro.enabled, let found {
            self.disabledWarning =
                "Disabled -- \(self.triggerLabel) on \(self.layerLabel) does nothing until re-enabled."
        } else {
            self.disabledWarning = nil
        }
```

Note the existing initializer assigns `triggerLabel`/`layerLabel` inside the
`if let found` branch above; place this block after that `if`/`else` so both
are already set.

Then rework `MacroLibraryRowView`. Its parameters become:

```swift
    var row: MacroLibraryRow
    var chrome: Chrome
    var collections: [String]
    var isOverCapacity: Bool
    var open: () -> Void
    var setEnabled: (Bool) -> Void
    var setCollection: (String?) -> Void
    var duplicate: () -> Void
    var export: () -> Void
    var delete: () -> Void
```

and its body becomes a gesture-free outer `ZStack` holding the background
and an `HStack` whose *first* element is the tap target and whose remaining
elements are the controls — siblings, never nested inside it:

```swift
    /// The tappable region covers only the informational cells. The
    /// controls are siblings in the enclosing `HStack`, because a tap
    /// target cannot contain another one -- see this type's doc comment.
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(chrome.column)
            HStack(spacing: 0) {
                ZStack {
                    Color.clear
                    HStack(spacing: 0) {
                        cell(row.name, width: 240, weight: .semibold,
                             color: row.isEnabled ? chrome.textPrimary : chrome.textTertiary)
                        cell(row.triggerLabel, width: 130,
                             color: row.isBound ? chrome.textSecondary : chrome.textTertiary)
                        cell("\(row.stepCount)", width: 90, color: chrome.textSecondary)
                        cell("\(row.byteCount)", width: 90,
                             color: isOverCapacity ? chrome.dangerText : chrome.textSecondary)
                    }
                }
                .onHover { _ in }
                .onTapGesture(perform: open)

                collectionPicker
                Toggle("", isOn: Binding(get: { row.isEnabled }, set: setEnabled))
                    .toggleStyle(.switch)
                    .fixedSize()
                    .help("Disabled macros aren't uploaded, and free their bytes.")
                glyph("⧉", action: duplicate, help: "Duplicate this macro")
                glyph("↑", action: export, help: "Export this macro to a file")
                glyph("🗑", action: delete, help: "Delete this macro", color: chrome.dangerText)
                Spacer(minLength: 0)
            }
            .padding(EdgeInsets(top: 10, bottom: 10, leading: 16, trailing: 16))
        }
        .frame(height: row.disabledWarning == nil ? 40 : 56)
        .opacity(row.isEnabled ? 1.0 : 0.55)
    }

    private var collectionPicker: some View {
        // "--" is the ungrouped option. The list is derived from what
        // macros actually use (`KeymapDocument.macroCollections`), so an
        // emptied collection disappears from every row's picker on its own.
        Picker(
            of: [Self.ungrouped] + collections,
            selection: Binding(
                get: { row.collection ?? Self.ungrouped },
                set: { choice in
                    guard let choice else { return }
                    setCollection(choice == Self.ungrouped ? nil : choice)
                }
            )
        )
        .frame(width: 130)
    }

    private static let ungrouped = "--"

    private func glyph(_ text: String, action: @escaping () -> Void,
                       help: String, color: Color? = nil) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(color ?? chrome.textSecondary)
            .padding(.trailing, 12)
            .onTapGesture(perform: action)
            .help(help)
    }
```

The LAYER column is dropped from the row to make room; its information is
already in `triggerLabel`'s neighbour and now also appears in
`disabledWarning`. Render `disabledWarning` beneath the name cell when
present — a second `Text` inside that inner `HStack`'s first column is not
possible without breaking the two-child rule, so make the name cell a
`VStack` of name + optional warning and keep the `ZStack`'s two children
intact.

Update the `columnHeader` labels to match the new columns: `MACRO` (240),
`TRIGGER` (130), `STEPS` (90), `BYTES` (90), `COLLECTION` (130), `ON` (60).

Update `MacroLibraryView`'s `ForEach` to pass the new closures:

```swift
                            MacroLibraryRowView(
                                row: row,
                                chrome: chrome,
                                collections: editor.document.macroCollections,
                                isOverCapacity: capacityWarning != nil,
                                open: { editor.openMacro(id: row.id) },
                                setEnabled: { editor.setMacroEnabled(id: row.id, $0) },
                                setCollection: { editor.setMacroCollection(id: row.id, $0) },
                                duplicate: { editor.duplicateMacro(id: row.id) },
                                export: { exportMacro(row) },
                                delete: { confirmDelete(row) }
                            )
```

with the export helper on `MacroLibraryView` (it needs the file chooser, so
add `@Environment(\.chooseFileSaveDestination) private var chooseFileSaveDestination`
to the view):

```swift
    private func exportMacro(_ row: MacroLibraryRow) {
        Task {
            guard
                let macro = editor.document.macroList.first(where: { $0.id == row.id }),
                let url = await chooseFileSaveDestination(
                    title: "Export macro",
                    defaultFileName: "\(macro.name).json")
            else { return }
            editor.exportMacro(macro, to: url)
        }
    }
```

- [ ] **Step 4: Run tests and the app**

Run: `swift test --build-system native`
Expected: PASS.

Then run: `swift run --build-system native SMKConfigurator`, open the MACROS
rail tab, and confirm by eye: rows are still clickable and open the step
editor, the toggle flips, the collection picker opens, and a disabled row
dims. Click delivery through a restructured row is exactly what broke here
before and no test covers it.

- [ ] **Step 5: Commit**

```bash
git add Sources/SMKConfigurator/Model/Macro.swift Sources/SMKConfigurator/Views/MacroLibraryView.swift Tests/SMKConfiguratorTests/MacroLibraryFilterTests.swift
git commit -m "Give library rows enable, collection, duplicate and export controls"
```

---

### Task 8: Search and collection filtering

**Files:**
- Modify: `Sources/SMKConfigurator/Views/MacroLibraryView.swift` (add
  `MacroLibraryFilter` above `MacroLibraryView`)
- Test: `Tests/SMKConfiguratorTests/MacroLibraryFilterTests.swift` (add a
  second suite to the file created in Task 7)

**Interfaces:**
- Consumes: `MacroLibraryRow.searchText`/`collection` (Task 7).
- Produces:
  - `struct MacroLibraryFilter: Equatable` with `var query: String = ""`,
    `var collection: String? = nil`
  - `func apply(to rows: [MacroLibraryRow]) -> [MacroLibraryRow]`

Kept as a plain value type with a pure method so filtering is testable
without standing up a view — the same reason `MacroLibraryRow` derives its
strings up front.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/SMKConfiguratorTests/MacroLibraryFilterTests.swift`:

```swift
@Suite("Filtering the macro library")
struct MacroLibraryFilterTests {
    private func rows() -> [MacroLibraryRow] {
        let macros = [
            MacroDefinition(id: 0, name: "Sign off", steps: [
                .text("kind regards", delivery: .keystrokes, msPerChar: 10)
            ], collection: "Work"),
            MacroDefinition(id: 1, name: "Build", steps: [.delay(ms: 20)],
                            collection: "Dev"),
            MacroDefinition(id: 2, name: "Ungrouped one", steps: []),
        ]
        let document = KeymapDocument(
            matrix: .init(rows: [0], cols: [1], colsAreDriven: 1),
            layers: [[["none"]]],
            macros: macros)
        return macros.map { MacroLibraryRow(macro: $0, document: document) }
    }

    @Test("an empty filter keeps everything")
    func emptyFilterKeepsAll() {
        #expect(MacroLibraryFilter().apply(to: rows()).count == 3)
    }

    @Test("search matches the name, case-insensitively")
    func searchMatchesName() {
        var filter = MacroLibraryFilter()
        filter.query = "SIGN"
        #expect(filter.apply(to: rows()).map(\.id) == [0])
    }

    @Test("search matches step content, not just the name")
    func searchMatchesStepContent() {
        var filter = MacroLibraryFilter()
        filter.query = "regards"
        #expect(filter.apply(to: rows()).map(\.id) == [0])
    }

    @Test("whitespace-only search is treated as no search")
    func blankSearchKeepsAll() {
        var filter = MacroLibraryFilter()
        filter.query = "   "
        #expect(filter.apply(to: rows()).count == 3)
    }

    @Test("a collection filter keeps only that collection")
    func collectionFilters() {
        var filter = MacroLibraryFilter()
        filter.collection = "Dev"
        #expect(filter.apply(to: rows()).map(\.id) == [1])
    }

    @Test("search and collection combine")
    func filtersCombine() {
        var filter = MacroLibraryFilter()
        filter.collection = "Work"
        filter.query = "build"
        #expect(filter.apply(to: rows()).isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --build-system native --filter MacroLibraryFilterTests`
Expected: FAIL — `cannot find 'MacroLibraryFilter' in scope`.

- [ ] **Step 3: Write the implementation**

Add above `MacroLibraryView` in `MacroLibraryView.swift`:

```swift
/// What the library header is currently filtering by. A plain value type
/// with a pure `apply(to:)` so the matching rules are testable without a
/// view, the same reason `MacroLibraryRow` derives its strings up front.
struct MacroLibraryFilter: Equatable {
    /// Free text matched against `MacroLibraryRow.searchText` -- the macro's
    /// name and every step's content, including steps nested inside a
    /// repeat block. Blank means "no search" rather than "match nothing".
    var query: String = ""

    /// `nil` means every collection. A named collection matches only macros
    /// assigned to it; ungrouped macros match no named collection.
    var collection: String? = nil

    func apply(to rows: [MacroLibraryRow]) -> [MacroLibraryRow] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return rows.filter { row in
            if let collection, row.collection != collection { return false }
            if needle.isEmpty { return true }
            return row.searchText.contains(needle)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --build-system native`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SMKConfigurator/Views/MacroLibraryView.swift Tests/SMKConfiguratorTests/MacroLibraryFilterTests.swift
git commit -m "Add search and collection filtering to the macro library"
```

---

### Task 9: The library header — search field, collection filter, import

**Files:**
- Modify: `Sources/SMKConfigurator/Views/MacroLibraryView.swift` (the
  `header` property, the `rows` property, the empty state)
- Test: manual (see Step 4) — this task adds no logic, only bindings to
  behaviour already covered by Tasks 5, 6 and 8.

**Interfaces:**
- Consumes: `MacroLibraryFilter` (Task 8), `EditorState.importMacro(from:)`
  (Task 6), `KeymapDocument.macroCollections` (Task 4).
- Produces: nothing other tasks consume — this is the last task.

- [ ] **Step 1: Add the filter state and wire the rows through it**

In `MacroLibraryView`, add the state and the chooser environment value, and
route `rows` through the filter:

```swift
    @Environment(\.chooseFile) private var chooseFile
    @State private var filter = MacroLibraryFilter()

    /// Every row, before filtering -- the count the empty states below
    /// distinguish "no macros at all" from "none match the filter" with.
    private var allRows: [MacroLibraryRow] {
        editor.document.macroList.map { MacroLibraryRow(macro: $0, document: editor.document) }
    }

    private var rows: [MacroLibraryRow] { filter.apply(to: allRows) }
```

- [ ] **Step 2: Add the header controls**

Replace `header`'s `Spacer()`-and-buttons tail so the search field and
collection picker sit between the budget summary and the action pills:

```swift
            Spacer()
            TextField("Search macros", text: Binding(
                get: { filter.query },
                set: { filter.query = $0 }
            ))
            .frame(width: 180)

            // "All" is not a collection, it is the absence of the filter.
            // The named options derive from what macros actually use, so an
            // emptied collection disappears from this picker on its own.
            Picker(
                of: [Self.allCollections] + editor.document.macroCollections,
                selection: Binding(
                    get: { filter.collection ?? Self.allCollections },
                    set: { choice in
                        guard let choice else { return }
                        filter.collection = (choice == Self.allCollections) ? nil : choice
                    }
                )
            )
            .frame(width: 140)

            ToolbarPill(label: "Record new", isEnabled: false, action: {})
                .help("Recording macros from the board isn't implemented yet.")
            ToolbarPill(label: "Import", action: importMacro)
            ToolbarPill(label: "New macro", isAccent: true, action: editor.createMacro)
```

and add to the view:

```swift
    private static let allCollections = "All"

    private func importMacro() {
        Task {
            guard let url = await chooseFile(title: "Import macro JSON",
                                             allowSelectingFiles: true)
            else { return }
            editor.importMacro(from: url)
        }
    }
```

- [ ] **Step 3: Distinguish the two empty states**

An empty table means two different things now, and saying "No macros yet" to
someone whose search simply matched nothing is actively misleading — it reads
as data loss. Replace `emptyState`:

```swift
    private var emptyState: some View {
        Text(allRows.isEmpty
             ? "No macros yet. Create one to place it on a key."
             : "No macros match this search or collection.")
            .font(.system(size: 12))
            .foregroundColor(chrome.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
```

- [ ] **Step 4: Build, test, and check by hand**

Run: `swift test --build-system native`
Expected: PASS — no behaviour changed, so nothing should move.

Run: `swift run --build-system native SMKConfigurator`, and in the MACROS
tab confirm:
- typing in the search field narrows the table, and clearing it restores
- the collection picker lists only collections actually in use, and "All"
  restores every row
- Import opens a file chooser; importing a macro exported from a row adds it
  in a new slot with its name intact
- with a search active that matches nothing, the table says so rather than
  claiming there are no macros

- [ ] **Step 5: Commit**

```bash
git add Sources/SMKConfigurator/Views/MacroLibraryView.swift
git commit -m "Add search, collection filter and import to the library header"
```

---

## Done when

- `swift test --build-system native` passes, including
  `BinaryFormatAgreementTests` (the cross-repo byte agreement must be
  untouched by everything above).
- Opening and saving a `keymap.json` with no `enabled`/`collection` fields
  produces a byte-identical file.
- A disabled macro's bytes come back: with one macro disabled, the library
  header's byte figure drops by that macro's size.
- `~/esp/SMK` is untouched by this plan.

## Deliberately not in this plan

- **Reordering macros.** Slot order is id order, and ids are a firmware
  resource, not a display concern (spec, "Out of scope").
- **Sharing collections between documents.** A collection is a string on a
  macro; there is no collection object to share.
- **Recording from the board** (sub-project 4, blocked on hardware) and
  **conditional flows** (sub-project 5, needs the host helper).
