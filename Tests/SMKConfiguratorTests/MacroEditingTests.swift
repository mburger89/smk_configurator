import Foundation
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

    @Test("deleting a macro frees its slot for reuse")
    func deleteMacroFreesSlot() {
        let e = editor()
        e.createMacro()   // id 0
        e.closeMacro()
        e.createMacro()   // id 1
        e.deleteMacro(id: 0)
        #expect(e.document.macroList.map(\.id) == [1])
        #expect(e.document.nextMacroID == 0)
    }

    @Test("deleting the macro being edited closes the editor")
    func deletingOpenMacroClosesEditor() {
        let e = editor()
        e.createMacro()   // id 0, now open
        e.deleteMacro(id: 0)
        #expect(e.macroWorkspace == .library)
    }

    @Test("deleting a different macro leaves the open one alone")
    func deletingOtherMacroKeepsEditorOpen() {
        let e = editor()
        e.createMacro()   // id 0
        e.closeMacro()
        e.createMacro()   // id 1, now open
        e.deleteMacro(id: 0)
        #expect(e.macroWorkspace == .editor(id: 1))
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

    @Test("compiling a document with macros produces bytes whose macroCount header byte is non-zero")
    func compiledPayloadIncludesMacroCount() throws {
        let e = editor()
        e.createMacro()
        e.updateMacro(MacroDefinition(id: 0, name: "Hi", steps: [.delay(ms: 5)]))

        let bytes = try e.compileForUpload()
        // Header layout (see compileKeymap): rowCount, colCount,
        // colsAreDriven, layerCount, macroCount, reserved.
        #expect(bytes[4] != 0)
    }

    @Test("a document with no macros compiles a payload whose macroCount header byte is zero")
    func compiledPayloadOmitsAbsentMacros() throws {
        let e = editor()
        let bytes = try e.compileForUpload()
        #expect(bytes[4] == 0)
    }

    @Test("inserting after a stale, out-of-range selection still clamps in bounds")
    func insertClampsStaleSelection() {
        let e = editor()
        e.createMacro()
        e.appendStep(.delay(ms: 1))
        e.appendStep(.delay(ms: 2))
        e.selectedStepIndex = 10 // stale -- further out than the array ever was
        e.insertStepAfterSelection(.delay(ms: 3))
        #expect(e.document.macroList[0].steps == [.delay(ms: 1), .delay(ms: 2), .delay(ms: 3)])
        #expect(e.selectedStepIndex == 2)
    }

    @Test("appending does nothing when no macro is open")
    func appendStepNoopWithoutOpenMacro() {
        let e = editor()
        e.appendStep(.delay(ms: 1))
        #expect(e.selectedStepIndex == nil)
        #expect(e.document.macroList.isEmpty)
    }

    @Test("opening a macro with steps selects the first one")
    func openMacroSelectsFirstStep() {
        let e = editor()
        e.createMacro() // id 0
        e.appendStep(.delay(ms: 1))
        e.closeMacro()
        e.openMacro(id: 0)
        #expect(e.macroWorkspace == .editor(id: 0))
        #expect(e.selectedStepIndex == 0)
    }

    @Test("opening an empty macro leaves the selection nil")
    func openMacroEmptyLeavesSelectionNil() {
        let e = editor()
        e.createMacro() // id 0, empty
        e.closeMacro()
        e.openMacro(id: 0)
        #expect(e.macroWorkspace == .editor(id: 0))
        #expect(e.selectedStepIndex == nil)
    }

    @Test("opening a macro id that doesn't exist is a no-op")
    func openMacroNonexistentIsNoop() {
        let e = editor()
        e.openMacro(id: 42)
        #expect(e.macroWorkspace == .library)
        #expect(e.selectedStepIndex == nil)
    }

    @Test("an over-capacity document refuses to upload and reports why")
    func sendToDeviceRefusesOverCapacity() {
        let e = editor()
        e.macroCapacity = MacroCapacity(macroBytes: 4, macroSlots: 8)
        e.createMacro()
        e.updateMacro(MacroDefinition(id: 0, name: "too big for four bytes",
                                      steps: [.delay(ms: 1), .delay(ms: 2)]))
        #expect(e.macroBudget.canFlash == false)

        e.sendToDevice()

        #expect(e.isSendingToDevice == false)
        #expect(e.loadError == e.macroBudget.blockReason)
    }

    @Test("an in-capacity document clears the guard without touching a transport")
    func sendToDeviceGuardPassesWithinCapacity() {
        // Deliberately does NOT call sendToDevice(): that method spawns a
        // Task that constructs a real USBRawHIDTransport and, if a board is
        // physically connected, runs the full BEGIN/CHUNK/COMMIT upload --
        // overwriting whatever keymap is on the keyboard with this test's
        // throwaway 1x1 "none" document. Asserting on the guard's observable
        // effect (macroBudget.canFlash / loadError) instead exercises the
        // same guard logic as sendToDeviceRefusesOverCapacity above without
        // ever risking hardware.
        let e = editor()
        #expect(e.macroBudget.canFlash == true)
        #expect(e.loadError == nil)
    }

    @Test("a document green on a believed capacity larger than the real device limit is still refused by the payload-size guard, blaming macros")
    func sendToDeviceRefusesOversizedCompiledPayloadEvenWithinMacroByteBudget() throws {
        // This used to demonstrate a different gap: MacroBudget summed only
        // MacroDefinition.compiledSize, never adding in the layers sharing
        // the same wire budget, so it could read green while the true
        // compiled payload (layers + macros) overflowed the wire limit. That
        // gap is closed now -- MacroBudget measures against the whole
        // document (see its doc comment) and reduces headroom by what
        // layers actually cost.
        //
        // The residual gap this test now demonstrates is different: the
        // *believed* capacity itself (`macroCapacity`, whatever this app
        // currently thinks the board can hold -- live, remembered, or
        // guessed) can simply be larger than `KeymapUploader.maxPayloadLength`,
        // this build's own fixed wire ceiling. Here it's set to 6000, well
        // above the real 4085-byte limit, modeling a stale `.lastKnown`
        // capacity left over from a different, larger-flash board. Even a
        // fully layer-aware MacroBudget reads green against a wrong belief
        // like that, so `sendToDevice`'s separate payload-size guard is what
        // actually protects the wire limit.
        let e = editor()
        e.macroCapacity = MacroCapacity(macroBytes: 6000, macroSlots: 16)
        e.document.macros = (0..<5).map { id in
            MacroDefinition(
                id: id, name: "",
                steps: (0..<200).map { _ in .keystroke(mods: [], key: .a, holdMs: 40) }
            )
        }
        // Green: layers here are a single 1x1 "none" cell (a handful of
        // bytes), so even with MacroBudget correctly charging that against
        // the 6000-byte believed capacity, 5 x 1003 = 5015 compiled macro
        // bytes still fits comfortably.
        #expect(e.macroBudget.canFlash == true)

        e.sendToDevice()

        #expect(e.isSendingToDevice == false)
        let message = try #require(e.loadError)
        #expect(message.contains("macro"))
        #expect(message.contains("4085"))
    }

    @Test("a document with an unrecognized token makes sendToDevice report the compiler's message and never construct a transport")
    func sendToDeviceRefusesUnrecognizedToken() throws {
        let e = editor()
        e.document.layers[0][0][0] = "totally-bogus-token"

        e.sendToDevice()

        #expect(e.isSendingToDevice == false)
        let message = try #require(e.loadError)
        #expect(message.contains("totally-bogus-token"))
    }

    @Test("a macro that overflows a one-byte bytecode field is refused even though it's within capacity and JSON size")
    func sendToDeviceRefusesOverflowingMacro() {
        let e = editor()
        // A repeat count of 300 doesn't fit MacroStep's one-byte `count`
        // field, but the macro is tiny -- comfortably under both the
        // compiled-bytecode budget and the JSON upload limit -- so neither
        // of the other two guards would catch it. Only the overflow check
        // can.
        e.document.macros = [
            MacroDefinition(id: 0, name: "m", steps: [.repeatBlock(count: 300, steps: [.delay(ms: 1)])]),
        ]
        #expect(e.macroBudget.canFlash == true)

        e.sendToDevice()

        #expect(e.isSendingToDevice == false)
        let expected = MacroOverflow.repeatCountTooLarge(count: 300).message
        #expect(e.loadError == expected)
    }

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

    @Test("the inspector offers three tabs in design order")
    func inspectorTabs() {
        #expect(MacroInspectorTab.allCases.map(\.label) == ["Step", "Macro", "Timing"])
    }

    @Test("loading a keymap from disk closes any open macro workspace")
    func loadResetsMacroWorkspace() throws {
        let e = editor()
        e.createMacro()
        e.appendStep(.delay(ms: 1))
        #expect(e.macroWorkspace != .library)
        #expect(e.selectedStepIndex != nil)

        let doc = KeymapDocument(
            matrix: .init(rows: [0], cols: [1], colsAreDriven: 1),
            layers: [[["none"]]]
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacroEditingTests-\(UUID().uuidString).json")
        try JSONEncoder().encode(doc).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        e.load(from: url)

        #expect(e.macroWorkspace == .library)
        #expect(e.selectedStepIndex == nil)
    }

    @Test("starting a new document closes any open macro workspace")
    func newDocumentResetsMacroWorkspace() {
        let e = editor()
        e.createMacro()
        e.appendStep(.delay(ms: 1))
        #expect(e.macroWorkspace != .library)
        #expect(e.selectedStepIndex != nil)

        e.newDocument()

        #expect(e.macroWorkspace == .library)
        #expect(e.selectedStepIndex == nil)
    }

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
}
