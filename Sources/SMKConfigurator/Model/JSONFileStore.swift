import Foundation

/// Persists a collection of named, Codable items as one JSON file per item
/// in a directory -- the shared shape behind both `KeyboardDesign` and
/// `KeyboardTheme` storage (`~/Library/Application Support/SMKConfigurator/{Designs,Themes}`).
struct JSONFileStore<T: Codable>: Sendable {
    var directory: URL
    var nameOf: @Sendable (T) -> String

    func fileName(for item: T) -> String {
        let sanitized = nameOf(item)
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "_" }
            .reduce(into: "") { $0.append($1) }
        return "\(sanitized.isEmpty ? "item" : sanitized).json"
    }

    /// Writes `defaults` into the directory only if it doesn't already
    /// contain any `.json` files, so a fresh install ships with presets
    /// that the user can freely edit/delete afterwards.
    func ensureSeeded(with defaults: [T]) {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let existing = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        guard existing.filter({ $0.pathExtension == "json" }).isEmpty else { return }
        for item in defaults {
            try? save(item)
        }
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
