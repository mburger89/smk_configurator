import Foundation

/// Persists a collection of named, Codable items as one JSON file per item
/// in a directory -- the shared shape behind both `KeyboardDesign` and
/// `KeyboardTheme` storage (`~/Library/Application Support/SMKConfigurator/{Designs,Themes}`).
struct JSONFileStore<T: Codable>: Sendable {
    var directory: URL
    var nameOf: @Sendable (T) -> String

    /// Where the seeded-names record (below) is stored. Defaults to the real
    /// app domain in production; tests inject a throwaway `UserDefaults(
    /// suiteName:)` domain so they never touch persistent developer-machine
    /// state. Named `userDefaults` (not `defaults`) to avoid shadowing
    /// `ensureSeeded(with defaults:)`'s parameter of the same name below.
    /// `UserDefaults` is documented thread-safe but predates `Sendable` and
    /// isn't marked as conforming, so `nonisolated(unsafe)` is needed for
    /// this `Sendable`-conforming struct to hold one as a stored property.
    nonisolated(unsafe) var userDefaults: UserDefaults = .standard

    func fileName(for item: T) -> String {
        let sanitized = nameOf(item)
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "_" }
            .reduce(into: "") { $0.append($1) }
        return "\(sanitized.isEmpty ? "item" : sanitized).json"
    }

    /// `UserDefaults` key remembering which built-in names this store has
    /// ever seeded, so a later app update that adds a new built-in (e.g.
    /// `smk_test_board` after `gateron_lp_kbd`-only installs already
    /// existed) can backfill it into existing installs -- keyed by the
    /// directory's absolute path so Designs and Themes (and any test-only
    /// temp directories) each get an independent record.
    private var seededNamesDefaultsKey: String { "JSONFileStore.seededNames.\(directory.path)" }

    /// Writes any of `defaults` this store has never seeded before into the
    /// directory, then records their names so they're never written again --
    /// covers both a fresh install (nothing seeded yet) and an existing
    /// install upgrading to a version that adds a new built-in.
    ///
    /// Two things are true regardless of which case this is:
    /// - a name already on disk is never overwritten (protects a
    ///   user-edited built-in), and
    /// - a name already recorded as seeded is never written again, even if
    ///   its file is gone (respects a deliberate delete).
    ///
    /// The one case this can't distinguish is a name that both predates
    /// this tracking *and* was deleted before the app was ever updated to a
    /// version that records it: since no record exists yet, its absence
    /// looks identical to "never seeded", and it gets recreated. That's a
    /// one-time migration edge case for built-ins that existed before this
    /// mechanism shipped -- every name added after this ships is tracked
    /// from the moment it first appears in `defaults`, so deleting it always
    /// sticks from then on.
    func ensureSeeded(with defaults: [T]) {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)

        var seededNames = Set(userDefaults.stringArray(forKey: seededNamesDefaultsKey) ?? [])
        for item in defaults {
            let name = nameOf(item)
            guard !seededNames.contains(name) else { continue }
            let destination = directory.appendingPathComponent(fileName(for: item))
            if !fm.fileExists(atPath: destination.path) {
                try? save(item)
            }
            seededNames.insert(name)
        }
        userDefaults.set(Array(seededNames), forKey: seededNamesDefaultsKey)
    }

    func loadAll(fallback: [T]) -> [T] {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        let items = urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> T? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(T.self, from: data)
            }
        return items.isEmpty ? fallback : items
    }

    func save(_ item: T) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(item)
        try data.write(to: directory.appendingPathComponent(fileName(for: item)), options: .atomic)
    }

    func delete(_ item: T) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(fileName(for: item)))
    }
}
