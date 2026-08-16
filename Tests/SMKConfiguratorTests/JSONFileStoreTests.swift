import Foundation
import Testing
@testable import SMKConfigurator

/// Exercises `JSONFileStore.ensureSeeded`'s backfill behaviour -- the fix
/// for `smkTestBoard` being unreachable for anyone who already had a
/// Designs directory (see `KeyboardDesignTests` for the design's own
/// shape/matrix contract).
@Suite("JSONFileStore.ensureSeeded backfills new built-ins without clobbering user state")
struct JSONFileStoreTests {
    /// A fresh, uniquely-named directory per test so none of them can see
    /// each other's files, plus a throwaway `UserDefaults(suiteName:)`
    /// domain (rather than `.standard`) so the seeded-names record never
    /// touches real, persistent developer-machine/CI state.
    func makeTempStore() -> (store: JSONFileStore<KeyboardDesign>, directory: URL, defaultsSuite: String) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("JSONFileStoreTests-\(UUID().uuidString)", isDirectory: true)
        let defaultsSuite = "JSONFileStoreTests-\(UUID().uuidString)"
        let store = JSONFileStore<KeyboardDesign>(
            directory: directory,
            nameOf: { $0.name },
            userDefaults: UserDefaults(suiteName: defaultsSuite)!
        )
        return (store, directory, defaultsSuite)
    }

    func cleanUp(_ directory: URL, _ defaultsSuite: String) {
        try? FileManager.default.removeItem(at: directory)
        UserDefaults().removePersistentDomain(forName: defaultsSuite)
    }

    @Test("existing store with only gateronLPKBD gains smkTestBoard, and matrix-based selection lands on it")
    func backfillsNewBuiltInForExistingStore() throws {
        let (store, directory, defaultsSuite) = makeTempStore()
        defer { cleanUp(directory, defaultsSuite) }

        // Simulate an existing user: a Designs directory that already
        // contains gateronLPKBD and nothing else -- exactly the state the
        // original seed-only-if-empty logic would have left them in.
        try store.save(.gateronLPKBD)

        // The fix under test: seeding with the fuller default list should
        // reach into that already-non-empty directory and add the new
        // built-in, rather than bailing out because *something* exists.
        store.ensureSeeded(with: [.gateronLPKBD, .smkTestBoard])

        let designs = store.loadAll(fallback: [])
        #expect(designs.contains { $0.name == "smk_test_board" })
        #expect(designs.contains { $0.name == "gateron_lp_kbd" })

        // The actual behaviour that matters end-to-end: a 3x3 document
        // matching the test board's matrix must select smkTestBoard via
        // EditorState's `availableDesigns.first { $0.matrix == doc.matrix }`
        // lookup, not fall through to genericGrid.
        let testBoardMatrix = KeymapDocument.Matrix(rows: [1, 2, 21], cols: [22, 23, 16], colsAreDriven: 1)
        let selected = designs.first { $0.matrix == testBoardMatrix } ?? .genericGrid(matrix: testBoardMatrix)
        #expect(selected.name == "smk_test_board")
        #expect(selected == KeyboardDesign.smkTestBoard)
    }

    @Test("a user-edited built-in is never overwritten by re-seeding")
    func doesNotClobberUserEdits() throws {
        let (store, directory, defaultsSuite) = makeTempStore()
        defer { cleanUp(directory, defaultsSuite) }

        var customized = KeyboardDesign.gateronLPKBD
        customized.grid[0][0].width = 3.5
        try store.save(customized)

        store.ensureSeeded(with: [.gateronLPKBD, .smkTestBoard])

        let designs = store.loadAll(fallback: [])
        let reloaded = designs.first { $0.name == "gateron_lp_kbd" }
        #expect(reloaded?.grid[0][0].width == 3.5)
    }

    @Test("deleting a backfilled built-in sticks across a later ensureSeeded call")
    func respectsDeletionAfterBackfill() throws {
        let (store, directory, defaultsSuite) = makeTempStore()
        defer { cleanUp(directory, defaultsSuite) }

        try store.save(.gateronLPKBD)
        store.ensureSeeded(with: [.gateronLPKBD, .smkTestBoard])
        #expect(store.loadAll(fallback: []).contains { $0.name == "smk_test_board" })

        // The user deliberately deletes the newly-backfilled design.
        store.delete(.smkTestBoard)
        #expect(!store.loadAll(fallback: []).contains { $0.name == "smk_test_board" })

        // Re-running ensureSeeded (e.g. the next app launch) must not
        // resurrect it, because its name is already recorded as seeded.
        store.ensureSeeded(with: [.gateronLPKBD, .smkTestBoard])
        #expect(!store.loadAll(fallback: []).contains { $0.name == "smk_test_board" })
    }

    @Test("fresh install still seeds every default")
    func freshInstallSeedsEverything() {
        let (store, directory, defaultsSuite) = makeTempStore()
        defer { cleanUp(directory, defaultsSuite) }

        store.ensureSeeded(with: [.gateronLPKBD, .smkTestBoard])

        let names = Set(store.loadAll(fallback: []).map { $0.name })
        #expect(names == ["gateron_lp_kbd", "smk_test_board"])
    }
}
