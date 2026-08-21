import Testing
@testable import SMKConfigurator

/// `MacroStepType` is the palette's step-type vocabulary (Task 10) -- kept
/// separate from `MacroEditingTests` (EditorState's macro-editing
/// operations) since it's a different subject: the palette's ordered,
/// badge-coloured list of step kinds, not editor state mutation.
@Suite("The step palette's five step types")
struct MacroStepTypeTests {
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
}
