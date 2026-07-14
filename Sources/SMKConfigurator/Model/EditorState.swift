import Foundation
import SwiftCrossUI

/// Default location this app is pointed at: the reference `keymap.json` in
/// the SMK firmware repo (see `~/esp/SMK/CLAUDE.md` -- copying it into
/// `Main.swift`'s `configJson` remains a manual step, by design).
let defaultKeymapURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("esp/SMK/keymap.json")

private let applicationSupportURL = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("SMKConfigurator", isDirectory: true)

let designStore = JSONFileStore<KeyboardDesign>(
    directory: applicationSupportURL.appendingPathComponent("Designs", isDirectory: true),
    nameOf: { $0.name }
)
let themeStore = JSONFileStore<KeyboardTheme>(
    directory: applicationSupportURL.appendingPathComponent("Themes", isDirectory: true),
    nameOf: { $0.name }
)

private let drawerHeightDefaultsKey = "drawerHeight"

@ObservableObject
class EditorState {
    static let drawerHeightRange: ClosedRange<Double> = 120...480

    var document: KeymapDocument
    var fileURL: URL?
    var isDirty: Bool = false
    var currentLayer: Int = 0
    var selectedToken: ActionToken? = nil
    /// Layer index used by the momentary/toggle layer palette tiles.
    var pendingLayerIndex: Int = 1
    var loadError: String? = nil

    /// Persisted across launches so the drawer stays the size you left it.
    var drawerHeight: Double {
        didSet { UserDefaults.standard.set(drawerHeight, forKey: drawerHeightDefaultsKey) }
    }

    var activeDesign: KeyboardDesign
    var availableDesigns: [KeyboardDesign] = []

    var activeTheme: KeyboardTheme
    var availableThemes: [KeyboardTheme] = []

    init() {
        let storedHeight = UserDefaults.standard.object(forKey: drawerHeightDefaultsKey) as? Double ?? 260
        let range = Self.drawerHeightRange
        self.drawerHeight = min(max(storedHeight, range.lowerBound), range.upperBound)

        designStore.ensureSeeded(with: [.gateronLPKBD])
        themeStore.ensureSeeded(with: KeyboardTheme.allBuiltIns)

        let designs = designStore.loadAll(fallback: [.gateronLPKBD])
        let themes = themeStore.loadAll(fallback: KeyboardTheme.allBuiltIns)
        self.availableDesigns = designs
        self.availableThemes = themes
        self.activeTheme = themes.first { $0.name == "Default" } ?? themes[0]

        if let data = try? Data(contentsOf: defaultKeymapURL),
           let doc = try? JSONDecoder().decode(KeymapDocument.self, from: data) {
            self.document = doc
            self.fileURL = defaultKeymapURL
            self.activeDesign = designs.first { $0.matrix == doc.matrix }
                ?? .genericGrid(matrix: doc.matrix)
        } else {
            let design = designs.first ?? .gateronLPKBD
            self.activeDesign = design
            self.document = .blank(for: design)
            self.fileURL = nil
        }
    }

    // MARK: - Keymap file I/O

    func load(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let doc = try JSONDecoder().decode(KeymapDocument.self, from: data)
            document = doc
            fileURL = url
            currentLayer = 0
            isDirty = false
            loadError = nil
            activeDesign = availableDesigns.first { $0.matrix == doc.matrix }
                ?? .genericGrid(matrix: doc.matrix)
        } catch {
            loadError = "Couldn't load \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    @discardableResult
    func save(to url: URL) -> Bool {
        guard writeJSON(document, to: url, errorContext: "save \(url.lastPathComponent)") else { return false }
        fileURL = url
        isDirty = false
        return true
    }

    func newDocument() {
        document = .blank(for: activeDesign)
        fileURL = nil
        currentLayer = 0
        isDirty = false
    }

    // MARK: - Keymap editing

    func assign(_ token: ActionToken, row: Int, col: Int) {
        guard currentLayer < document.layers.count,
              row < document.layers[currentLayer].count,
              col < document.layers[currentLayer][row].count
        else { return }
        document.layers[currentLayer][row][col] = token.canonicalString
        isDirty = true
    }

    func action(row: Int, col: Int) -> ActionToken {
        guard currentLayer < document.layers.count,
              row < document.layers[currentLayer].count,
              col < document.layers[currentLayer][row].count
        else { return .none }
        return ActionToken.parse(document.layers[currentLayer][row][col])
    }

    func addLayer() {
        document.layers.append(KeymapDocument.blankTransparentLayer(for: activeDesign))
        currentLayer = document.layers.count - 1
        isDirty = true
    }

    func removeCurrentLayer() {
        guard document.layers.count > 1 else { return }
        document.layers.remove(at: currentLayer)
        currentLayer = min(currentLayer, document.layers.count - 1)
        isDirty = true
    }

    func toggleSelection(_ token: ActionToken) {
        selectedToken = (selectedToken == token) ? nil : token
    }

    // MARK: - Design management

    func selectDesign(_ design: KeyboardDesign) {
        activeDesign = design
        if document.matrix != design.matrix {
            document.matrix = design.matrix
            document.layers = document.layers.map { $0.reshaped(to: design) }
            isDirty = true
        }
    }

    func saveDesign(_ design: KeyboardDesign) {
        do {
            try designStore.save(design)
            availableDesigns = designStore.loadAll(fallback: [.gateronLPKBD])
            selectDesign(design)
        } catch {
            loadError = "Couldn't save design \"\(design.name)\": \(error.localizedDescription)"
        }
    }

    func duplicateDesign(_ design: KeyboardDesign, as newName: String) {
        var copy = design
        copy.name = newName
        saveDesign(copy)
    }

    func deleteDesign(_ design: KeyboardDesign) {
        designStore.delete(design)
        availableDesigns = designStore.loadAll(fallback: [.gateronLPKBD])
        if activeDesign.id == design.id {
            selectDesign(availableDesigns.first ?? .gateronLPKBD)
        }
    }

    func importDesign(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let design = try JSONDecoder().decode(KeyboardDesign.self, from: data)
            saveDesign(design)
        } catch {
            loadError = "Couldn't import design from \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func exportDesign(_ design: KeyboardDesign, to url: URL) {
        _ = writeJSON(design, to: url, errorContext: "export design \"\(design.name)\"")
    }

    // MARK: - Theme management

    func selectTheme(_ theme: KeyboardTheme) {
        activeTheme = theme
    }

    func saveTheme(_ theme: KeyboardTheme) {
        do {
            try themeStore.save(theme)
            availableThemes = themeStore.loadAll(fallback: KeyboardTheme.allBuiltIns)
            selectTheme(theme)
        } catch {
            loadError = "Couldn't save theme \"\(theme.name)\": \(error.localizedDescription)"
        }
    }

    func duplicateTheme(_ theme: KeyboardTheme, as newName: String) {
        var copy = theme
        copy.name = newName
        saveTheme(copy)
    }

    func deleteTheme(_ theme: KeyboardTheme) {
        themeStore.delete(theme)
        availableThemes = themeStore.loadAll(fallback: KeyboardTheme.allBuiltIns)
        if activeTheme.id == theme.id {
            selectTheme(availableThemes.first ?? .defaultTheme)
        }
    }

    func importTheme(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let theme = try JSONDecoder().decode(KeyboardTheme.self, from: data)
            saveTheme(theme)
        } catch {
            loadError = "Couldn't import theme from \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func exportTheme(_ theme: KeyboardTheme, to url: URL) {
        _ = writeJSON(theme, to: url, errorContext: "export theme \"\(theme.name)\"")
    }

    // MARK: - JSON I/O helper

    @discardableResult
    private func writeJSON<T: Encodable>(_ item: T, to url: URL, errorContext: String) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        do {
            try encoder.encode(item).write(to: url, options: .atomic)
            return true
        } catch {
            loadError = "Couldn't \(errorContext): \(error.localizedDescription)"
            return false
        }
    }
}
