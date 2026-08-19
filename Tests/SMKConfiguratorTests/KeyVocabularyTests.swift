import Foundation
import Testing
@testable import SMKConfigurator

/// The cross-repo agreement check that did not exist before this suite. KeyName
/// here and KeyCode in ~/esp/SMK are generated from one manifest; if they drift,
/// this app writes tokens the firmware parses as .noKey and the key silently
/// does nothing on a real keyboard, with no error anywhere.
@Suite("Key vocabulary agrees with the firmware manifest")
struct KeyVocabularyTests {

    /// Reads ~/esp/SMK/keycodes.json. Returns nil (rather than failing) when the
    /// firmware repo is not checked out beside this one, so CI on a runner with
    /// only this repo stays green.
    static func manifest() throws -> [[String: Any]]? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("esp/SMK/keycodes.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        return (obj as? [String: Any])?["keyboard"] as? [[String: Any]]
    }

    @Test("every KeyName case appears in the firmware manifest with the same usage")
    func namesMatchManifest() throws {
        guard let entries = try Self.manifest() else { return }
        let byToken = Dictionary(uniqueKeysWithValues: entries.compactMap { e -> (String, [String: Any])? in
            guard let t = e["token"] as? String else { return nil }
            return (t, e)
        })
        for name in KeyName.allCases {
            guard let entry = byToken[name.rawValue] else {
                Issue.record("KeyName.\(name) has no manifest entry")
                continue
            }
            // The check that matters: not just that both sides know the token,
            // but that they agree on which HID keycode it means.
            let manifestUsage = entry["usage"] as? Int ?? -1
            #expect(manifestUsage == Int(name.hidUsage),
                    "KeyName.\(name) is usage \(name.hidUsage) here, \(manifestUsage) in the manifest")
        }
        #expect(KeyName.allCases.count == entries.count)
    }

    @Test("usage values are pinned to the HID table")
    func usagesArePinned() throws {
        guard let entries = try Self.manifest() else { return }
        let usage = Dictionary(uniqueKeysWithValues: entries.compactMap { e -> (String, Int)? in
            guard let t = e["token"] as? String, let u = e["usage"] as? Int else { return nil }
            return (t, u)
        })
        #expect(usage["a"] == 0x04)
        #expect(usage["1"] == 0x1E)
        #expect(usage["backslash"] == 0x31)
        #expect(usage["semicolon"] == 0x33)
        #expect(usage["application"] == 0x65)
    }

    @Test("every KeyName is reachable from exactly one palette group")
    func everyKeyIsInExactlyOneGroup() {
        let grouped = KeyName.allGroups.flatMap(\.keys)
        for name in KeyName.allCases {
            #expect(grouped.filter { $0 == name }.count == 1,
                    "KeyName.\(name) is not in exactly one palette group")
        }
    }
}
