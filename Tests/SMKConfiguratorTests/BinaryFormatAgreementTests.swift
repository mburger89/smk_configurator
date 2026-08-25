import Foundation
import Testing
@testable import SMKConfigurator

/// The cross-repo agreement check for the binary keymap wire format.
///
/// Four independent implementations of this format now exist: this editor's
/// `compileKeymap` (`Sources/SMKConfigurator/Model/KeymapCompiler.swift`),
/// the firmware's decoder (`~/esp/SMK/Sources/SMKCore/KeymapBinary.swift`),
/// the firmware's build-time generator
/// (`~/esp/SMK/generate_default_keymap.sh`), and the firmware's test-only
/// encoder (`~/esp/SMK/Tests/SMKCoreTests/PayloadBuilder.swift`, pinned
/// against that generator by its own `builderMatchesShellGenerator` --
/// this suite covers the first three only). Nothing but a test keeps them
/// agreeing -- this format has already diverged once (an implementer, told
/// the layout lived in a doc that turned out to be on an unmerged branch,
/// invented an incompatible 0-based-tag scheme where the real contract uses
/// opcodes 0x01-0x05).
///
/// This suite follows `KeyVocabularyTests`'s pattern: it reaches into the
/// sibling `~/esp/SMK` checkout for a shared artifact, and skips (rather
/// than failing) when that repo is not present, so a checkout of only this
/// repo still gets a green suite.
///
/// Scope: `~/esp/SMK/keymap.json` (the shared input) carries no macros, so
/// this pins the header, matrix, and layer/cell encoding -- but *not* the
/// macro-entry encoding (opcodes 0x01-0x05, `encodeMacro`/`encodeMacroStep`
/// in `KeymapCompiler.swift`). That path is covered only by this repo's own
/// `KeymapCompilerTests`/`MacroCapacityTests`/`MacroStepTypeTests`, not by
/// cross-repo byte equality.
@Suite("Binary keymap format agrees with the firmware's generator")
struct BinaryFormatAgreementTests {

    enum FixtureError: Error, CustomStringConvertible {
        case noArrayLiteral
        case noElseBranch
        case noClosingBracket
        case invalidByte(String)

        var description: String {
            switch self {
            case .noArrayLiteral:
                return "DefaultKeymapGenerated.swift no longer contains " +
                    "\"let defaultKeymapBytes: [UInt8] = [\" -- generator output shape changed"
            case .noElseBranch:
                return "DefaultKeymapGenerated.swift has no \"#else\" branch -- the generator " +
                    "emits one #if chain over every board and the #else is smk_kbd, the board " +
                    "keymap.json describes and the one a flagless build compiles"
            case .noClosingBracket:
                return "DefaultKeymapGenerated.swift's byte array literal has no closing \"]\""
            case .invalidByte(let token):
                return "DefaultKeymapGenerated.swift's byte array contains a non-UInt8 token: \"\(token)\""
            }
        }
    }

    /// `~/esp/SMK`, or nil when the firmware repo is not checked out beside
    /// this one -- matching `KeyVocabularyTests.manifest()`'s skip pattern.
    static var firmwareRepo: URL? {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("esp/SMK")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Loads `~/esp/SMK/keymap.json` as a `KeymapDocument` -- the one input
    /// both encoders compile. Returns nil (not a failure) when the firmware
    /// repo, or this file within it, is absent.
    static func sharedKeymapDocument() throws -> KeymapDocument? {
        guard let repo = firmwareRepo else { return nil }
        let url = repo.appendingPathComponent("keymap.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(KeymapDocument.self, from: data)
    }

    /// Parses the `[UInt8]` literal out of the firmware's generated file as
    /// plain text -- this repo cannot `import SMKCore`, that module lives in
    /// the other repo's package. Deliberately strict: if the generator's
    /// output shape ever changes (different variable name, different
    /// bracket placement, a non-numeric token), this throws rather than
    /// silently matching against an empty or wrong array.
    ///
    /// Takes the array from the **`#else` branch specifically**, not the
    /// first one in the file. The generator emits one `#if`/`#elseif` chain
    /// over every board in `~/esp/SMK/boards/`, each branch declaring its own
    /// `defaultKeymapBytes`; the first branch is currently `nrf52840dk`.
    /// Three boards share `keymap.json`'s layers via `layersFrom` and differ
    /// only in their matrices, so matching the first branch compares this
    /// compiler's smk_kbd matrix against another board's and diverges at
    /// byte 2 (`colsAreDriven`) with byte-identical layers after it -- which
    /// is exactly what happened when the firmware's cJSON retirement turned
    /// a single-payload file into that chain. `#else` is smk_kbd: the board
    /// `keymap.json`'s `matrix` actually describes, and the payload a build
    /// with no `SMK_BOARD_*` flag compiles.
    static func parseGeneratedBytes(from text: String) throws -> [UInt8] {
        // Matched with its trailing newline: a bare "#else" is a prefix of
        // "#elseif", so the loose form finds the chain's second *branch*
        // (feather_nrf52840, a six-byte header) instead of its else.
        guard let elseRange = text.range(of: "\n#else\n") else {
            throw FixtureError.noElseBranch
        }
        let afterElse = text[elseRange.upperBound...]
        guard let markerRange = afterElse.range(of: "let defaultKeymapBytes: [UInt8] = [") else {
            throw FixtureError.noArrayLiteral
        }
        let afterMarker = afterElse[markerRange.upperBound...]
        guard let closeRange = afterMarker.range(of: "\n]") else {
            throw FixtureError.noClosingBracket
        }
        let body = afterMarker[..<closeRange.lowerBound]

        var bytes: [UInt8] = []
        for rawToken in body.split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == " " }) {
            let token = rawToken.trimmingCharacters(in: .whitespaces)
            guard !token.isEmpty else { continue }
            guard let value = UInt8(token) else {
                throw FixtureError.invalidByte(token)
            }
            bytes.append(value)
        }
        return bytes
    }

    /// Loads and parses `~/esp/SMK/Sources/SMKCore/DefaultKeymapGenerated.swift`.
    /// Returns nil (not a failure) when the firmware repo, or the generated
    /// file within it, is absent -- e.g. the firmware side of this two-repo
    /// change has not yet run `generate_default_keymap.sh`.
    static func generatedBytes() throws -> [UInt8]? {
        guard let repo = firmwareRepo else { return nil }
        let url = repo.appendingPathComponent("Sources/SMKCore/DefaultKeymapGenerated.swift")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let text = try String(contentsOf: url, encoding: .utf8)
        return try parseGeneratedBytes(from: text)
    }

    @Test("compileKeymap(keymap.json) equals the firmware's generated byte literal")
    func compiledBytesMatchGeneratedLiteral() throws {
        guard let document = try Self.sharedKeymapDocument(),
              let expected = try Self.generatedBytes() else { return }

        let actual = try compileKeymap(document)

        guard actual != expected else { return }

        let firstMismatch = zip(actual.indices, expected.indices)
            .first { actual[$0.0] != expected[$0.1] }?.0
        let context: String
        if let i = firstMismatch {
            let lo = max(0, i - 4)
            let aHi = min(actual.count, i + 5)
            let eHi = min(expected.count, i + 5)
            context = "first divergence at byte \(i): " +
                "this compiler produced \(Array(actual[lo..<aHi])), " +
                "firmware generator produced \(Array(expected[lo..<eHi]))"
        } else {
            context = "one sequence is a prefix of the other -- lengths differ (\(actual.count) vs \(expected.count))"
        }
        let message = """
            compileKeymap(keymap.json) disagrees with the firmware's DefaultKeymapGenerated.swift: \(context).
            this compiler (\(actual.count) bytes): \(actual)
            firmware generator (\(expected.count) bytes): \(expected)
            """
        Issue.record("\(message)")
    }
}
