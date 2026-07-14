import Foundation
import Testing
@testable import SMKConfigurator

@Suite("KeyboardTheme hex parsing and built-in preset round-trips")
struct KeyboardThemeTests {
    @Test("valid 6-digit hex with # parses to a color and reports valid")
    func validHexWithHash() {
        let color = ThemeColor(hex: "#FF79C6")
        #expect(color.isValid)
    }

    @Test("valid hex without a leading # still parses")
    func validHexWithoutHash() {
        let color = ThemeColor(hex: "44475A")
        #expect(color.isValid)
    }

    @Test("malformed hex is reported invalid rather than crashing", arguments: ["", "#ZZZZZZ", "#FFF", "not a color"])
    func malformedHexIsInvalid(hex: String) {
        let color = ThemeColor(hex: hex)
        #expect(!color.isValid)
    }

    @Test("every built-in theme has only valid hex colors", arguments: KeyboardTheme.allBuiltIns)
    func builtInThemesAreValid(theme: KeyboardTheme) {
        #expect(theme.background.isValid)
        #expect(theme.keyBackground.isValid)
        #expect(theme.keyText.isValid)
        #expect(theme.modifierBackground.isValid)
        #expect(theme.layerBackground.isValid)
        #expect(theme.specialBackground.isValid)
        #expect(theme.emptyBackground.isValid)
        #expect(theme.accent.isValid)
    }

    @Test("built-in theme names are unique")
    func builtInNamesAreUnique() {
        let names = Set(KeyboardTheme.allBuiltIns.map(\.name))
        #expect(names.count == KeyboardTheme.allBuiltIns.count)
    }

    @Test("JSON round-trip preserves every field", arguments: KeyboardTheme.allBuiltIns)
    func jsonRoundTrip(theme: KeyboardTheme) throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(theme)
        let decoded = try decoder.decode(KeyboardTheme.self, from: data)
        #expect(decoded == theme)
    }

    @Test("background(for:) covers every ActionToken case without crashing")
    func backgroundCoversAllTokenCases() {
        let theme = KeyboardTheme.defaultTheme
        let tokens: [ActionToken] = [
            .none, .transparent, .modifier(.leftShift),
            .momentaryLayer(1), .toggleLayer(2), .toggleConnection,
            .raw("key:f13"), .key(.a),
        ]
        for token in tokens {
            _ = theme.background(for: token)
        }
    }
}
