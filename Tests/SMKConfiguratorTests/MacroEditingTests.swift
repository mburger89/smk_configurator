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

    @Test("a document within capacity still proceeds to upload")
    func sendToDeviceProceedsWithinCapacity() {
        let e = editor()
        #expect(e.macroBudget.canFlash == true)

        e.sendToDevice()

        // Only the synchronous portion of sendToDevice() is observed here --
        // the guard passed and the in-flight flag flipped before any
        // transport work was scheduled. The async body then goes on to
        // touch real USB/BLE transports, which this test deliberately
        // does not await (see task-6-report.md for why).
        #expect(e.isSendingToDevice == true)
        #expect(e.loadError == nil)
    }
}
