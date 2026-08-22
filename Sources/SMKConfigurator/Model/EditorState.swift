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
private let showAdvancedDefaultsKey = "showAdvanced"
private let appearanceModeDefaultsKey = "appearanceMode"
/// Remembers which device (by `deviceKey`, see `applyDeviceCapacity(_:deviceKey:)`)
/// most recently reported real capacity, so `init()` knows which
/// `macroCapacity.<deviceKey>` entry to reload as `.lastKnown`.
private let macroCapacityLastDeviceKeyDefaultsKey = "macroCapacityLastDeviceKey"
private func macroCapacityDefaultsKey(forDeviceKey deviceKey: String) -> String {
    "macroCapacity.\(deviceKey)"
}

/// Mirrors the firmware build this app was written against (see
/// `KeymapUploader.maxPayloadLength`'s doc comment) — shown as a static
/// label in the status bar / Device pane, since the app has no way to read
/// a running firmware's version yet.
let firmwareVersionLabel = "v0.9.0"

/// Which of the four top-level workspaces the icon rail has selected. Drives
/// what the list/main/inspector columns render; everything else (selected
/// design/theme/layer/key, matrix values, theme role hex values) still lives
/// on `EditorState` exactly as before -- this only changes navigation.
enum RailMode: String, CaseIterable, Identifiable {
    case key, designs, themes, device, macros
    var id: String { rawValue }
}

/// Macros mode is the only rail mode with sub-states: the library takes the
/// whole workspace, and opening a macro swaps it for the step editor. Every
/// other rail mode renders one fixed layout.
enum MacroWorkspace: Equatable, Hashable {
    case library
    case editor(id: Int)

    var openMacroID: Int? {
        if case .editor(let id) = self { return id }
        return nil
    }
}

/// Light/Dark/System, set via the `View ▸ Appearance` menu (see `App.swift`)
/// and persisted across launches on `EditorState`.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case light, dark, system
    var id: String { rawValue }

    /// `nil` means "defer to the OS" — passed straight to `.preferredColorScheme`.
    var colorScheme: ColorScheme? {
        switch self {
            case .light: .light
            case .dark: .dark
            case .system: nil
        }
    }
}

/// A single physical key on the board, identified by its matrix position --
/// distinct from `selectedToken` (an action "armed" from the palette for
/// placement). This is "which keycap is the Inspector currently showing
/// details for".
struct KeyPosition: Equatable {
    var row: Int
    var col: Int
}

@MainActor
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

    /// Which rail mode (KEY/DSN/THM/DEV) the workspace is showing.
    var railMode: RailMode = .key
    /// Global "power detail" switch in the titlebar; hides matrix/GPIO/
    /// canonical-string detail in the Key inspector when off.
    var showAdvanced: Bool
    /// The physical key the Key inspector is currently showing, if any.
    var selectedKeyPosition: KeyPosition? = KeyPosition(row: 0, col: 0)

    /// Which of the MACROS workspace's two layouts (library vs. editor) is
    /// showing.
    var macroWorkspace: MacroWorkspace = .library
    /// Which step the inspector is editing, or nil when the macro is empty.
    var selectedStepIndex: Int? = nil
    /// Which tab of `MacroInspectorView` is showing. Lives here rather than
    /// as local `@State` on the inspector because `MacroCanvasHeaderView`'s
    /// "Test run" button (a sibling view, not an ancestor) needs to switch it
    /// to `.timing` -- there's no shared ancestor closer than `EditorState`.
    var macroInspectorTab: MacroInspectorTab = .step
    /// The last capacity a board reported, or the floor profile until one does.
    var macroCapacity: MacroCapacity = .floor
    var macroCapacitySource: MacroCapacitySource = .floor

    /// Light/Dark/System override for the whole app, applied via
    /// `.preferredColorScheme` at the app root (`App.swift`). Plain stored
    /// property (no `didSet`, same reason as `drawerHeight` below) — use
    /// `setAppearanceMode(_:)` to change it.
    var appearanceMode: AppearanceMode

    /// Whether a USB (RP2040) transport was reachable last time it was
    /// checked -- see `refreshDeviceStatus()`.
    var usbConnected: Bool = false
    #if canImport(CoreBluetooth)
    var bleState: BLEConnectionState = .idle
    var bleRSSI: Int?
    var bleMTU: Int?
    var blePeripheralName: String?
    #endif
    /// Non-nil only while an upload is in flight; drives the DEV pane's
    /// progress line. ~146 round trips for a 4 KB keymap.
    var uploadProgress: KeymapUploader.UploadPhase?
    var lastSentAt: Date? = nil

    /// Persisted across launches so the drawer stays the size you left it.
    /// Plain stored property (no `didSet`) -- the `@ObservableObject` macro
    /// explicitly skips properties with accessors, so a `didSet` here would
    /// silently stop it from publishing changes. Use `setDrawerHeight(_:)`
    /// to change it (assigns, then persists to `UserDefaults` separately).
    var drawerHeight: Double

    var activeDesign: KeyboardDesign
    var availableDesigns: [KeyboardDesign] = []

    var activeTheme: KeyboardTheme
    var availableThemes: [KeyboardTheme] = []

    /// Injected for tests -- a throwaway `UserDefaults(suiteName:)`,
    /// following `JSONFileStore`'s exact pattern -- so persistence round
    /// trips (drawer height, appearance, and macro capacity below) don't
    /// read or write the real user's `UserDefaults.standard` during
    /// `swift test`. Defaults to `.standard` for real app use.
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let storedHeight = userDefaults.object(forKey: drawerHeightDefaultsKey) as? Double ?? 260
        let range = Self.drawerHeightRange
        self.drawerHeight = min(max(storedHeight, range.lowerBound), range.upperBound)
        self.showAdvanced = userDefaults.object(forKey: showAdvancedDefaultsKey) as? Bool ?? false
        let storedAppearanceMode = userDefaults.string(forKey: appearanceModeDefaultsKey)
        self.appearanceMode = storedAppearanceMode.flatMap(AppearanceMode.init(rawValue:)) ?? .system

        // A board that reported real capacity in some earlier session --
        // possibly a previous launch entirely -- is remembered so this
        // session reports `.lastKnown` rather than dropping all the way
        // back to `MacroCapacity.floor` just because nothing is plugged in
        // right now. Superseded the moment a board answers `CAPS` again
        // (see `applyDeviceCapacity(_:deviceKey:)`).
        if let lastDeviceKey = userDefaults.string(forKey: macroCapacityLastDeviceKeyDefaultsKey),
           let data = userDefaults.data(forKey: macroCapacityDefaultsKey(forDeviceKey: lastDeviceKey)),
           let capacity = try? JSONDecoder().decode(MacroCapacity.self, from: data) {
            self.macroCapacity = capacity
            self.macroCapacitySource = .lastKnown
        }

        designStore.ensureSeeded(with: [.gateronLPKBD, .smkTestBoard])
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
            clampPendingLayerIndex()
            // The macro workspace (and whichever step it had selected) can
            // reference a macro id from the *previous* document -- e.g. a
            // step editor left open on macro 3 when the newly loaded file
            // has no macros at all, which would leave currentMacro nil and
            // strand the UI on a dead editor pane.
            macroWorkspace = .library
            selectedStepIndex = nil
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

    /// Writes the current document to `url` without changing `fileURL` or
    /// `isDirty` -- a "save a copy elsewhere" operation, distinct from
    /// `save(to:)`/Save As, for the titlebar's Export pill.
    func exportKeymap(to url: URL) {
        _ = writeJSON(document, to: url, errorContext: "export keymap")
    }

    func newDocument() {
        document = .blank(for: activeDesign)
        fileURL = nil
        currentLayer = 0
        clampPendingLayerIndex()
        // Same reasoning as load(from:) -- a fresh blank document has no
        // macros, so any macro workspace/step selection left over from
        // before must not survive the swap.
        macroWorkspace = .library
        selectedStepIndex = nil
        isDirty = false
    }

    // MARK: - Device upload

    var isSendingToDevice: Bool = false

    /// Tries USB (RP2040) first, then BLE (ESP32-C6), and pushes
    /// document.layers to whichever responds. Matrix data isn't sent — the
    /// firmware's matrix stays compiled-in (see the design spec).
    ///
    /// `macroBudget` gates *macro* compiled bytecode against the board's
    /// macro memory, but the wire format is now the same compiled bytecode
    /// for the *whole* document — matrix, every layer's cells, and macros —
    /// capped at `KeymapUploader.maxPayloadLength`. `macroBudget` only
    /// counts macro bytes, not the layers sharing that same budget, so a
    /// document can still read green on the macro meter while the full
    /// compiled payload is too big (e.g. many layers on a large matrix, or
    /// macros that individually fit the meter's ceiling but push the total
    /// past it). The payload is compiled and size-checked here,
    /// synchronously, before `isSendingToDevice` flips or the Task is
    /// created, so an oversized payload never touches a transport and the
    /// guard is observable without awaiting anything.
    ///
    /// Before either of those, every macro is checked against
    /// `MacroDefinition.overflows`: a one-byte bytecode field (a `.text`
    /// step's `msPerChar`, a `.repeatBlock`'s `count`, a macro's `id`, a
    /// `.layer` step's target index, plus the three checks the compiled/JSON
    /// guards already imply for name/step-count/payload length) can hold a
    /// value up to 255 no matter what the compiled-size or JSON-size meters
    /// say — a 300-count repeat is a handful of compiled bytes and JSON
    /// characters, small enough to sail through both of those, but wraps
    /// around in the one byte the firmware reads it into. UI sliders keep
    /// this from happening via the editor, but a decoded `keymap.json` isn't
    /// bound by the UI, so this guard runs synchronously here too, before
    /// `isSendingToDevice` flips or the Task is created — same reasoning as
    /// the JSON-size guard below.
    func sendToDevice() {
        let overflows = document.macroList.flatMap(\.overflows)
        guard overflows.isEmpty else {
            loadError = overflows.map(\.message).joined(separator: " ")
            return
        }
        guard macroBudget.canFlash else {
            loadError = macroBudget.blockReason
            return
        }
        guard !isSendingToDevice else { return }
        let payload: [UInt8]
        do {
            payload = try compileForUpload()
        } catch let compileError as KeymapCompileError {
            loadError = compileError.description
            return
        } catch {
            loadError = "Couldn't send keymap to device: \(error.localizedDescription)"
            return
        }
        guard payload.count <= KeymapUploader.maxPayloadLength else {
            loadError = "Keymap upload is \(payload.count) bytes, over the "
                + "\(KeymapUploader.maxPayloadLength)-byte device limit — the "
                + "macro meter only tracks macro bytes, not the layers sharing "
                + "the same budget, so it can read green while the compiled "
                + "keymap is still too big. Trim macro steps, delete unused "
                + "macros, or remove layers."
            return
        }
        isSendingToDevice = true
        Task { [self] in
            defer {
                isSendingToDevice = false
                uploadProgress = nil
                refreshDeviceStatus()
            }
            do {
                if let usb = try? USBRawHIDTransport() {
                    // Best-effort: a board's real capacity, learned the
                    // moment a transport is actually open. `try?` because
                    // older firmware built before the `CAPS` opcode existed
                    // simply won't answer it -- that must never fail an
                    // otherwise-good upload.
                    if let report = try? await KeymapUploader.queryCapacity(using: usb) {
                        applyDeviceCapacity(report, deviceKey: EditorState.usbDeviceKey)
                    }
                    try await KeymapUploader.upload(payload: payload, using: usb) { [weak self] phase in
                        self?.uploadProgress = phase
                    }
                } else {
                    #if canImport(CoreBluetooth)
                    let ble = BLETransport()
                    try await ble.connect()
                    if let report = try? await KeymapUploader.queryCapacity(using: ble) {
                        applyDeviceCapacity(report, deviceKey: bleDeviceKey)
                    }
                    try await KeymapUploader.upload(payload: payload, using: ble) { [weak self] phase in
                        self?.uploadProgress = phase
                    }
                    #else
                    throw DeviceTransportError.noDeviceFound
                    #endif
                }
                lastSentAt = Date()
            } catch {
                loadError = "Couldn't send keymap to device: \(error.localizedDescription)"
            }
        }
    }

    /// Cheap presence check (open + immediately allow to deinit/close) used
    /// by the Device pane/status bar to show a live connected/not-connected
    /// dot without holding a transport open across the whole app lifetime.
    func refreshDeviceStatus() {
        usbConnected = (try? USBRawHIDTransport()) != nil
        #if canImport(CoreBluetooth)
        bleState = BLECentral.shared.state
        bleRSSI = BLECentral.shared.rssi
        bleMTU = BLECentral.shared.mtu
        blePeripheralName = BLECentral.shared.peripheralName
        #endif
    }

    /// Non-destructive answer to "is the board reachable?" -- connects,
    /// discovers, and reports, without uploading anything.
    func testBLEConnection() {
        #if canImport(CoreBluetooth)
        Task {
            try? await BLECentral.shared.connect()
            refreshDeviceStatus()
        }
        #endif
    }

    /// The bytes the board receives: `compileKeymap(document)`'s binary
    /// payload (matrix, every layer's cells, and macros, all as fixed-width
    /// bytecode — see `Model/KeymapCompiler.swift`). Matrix *electrical*
    /// config (GPIO rows/cols) is included so the firmware can validate the
    /// payload against its own compiled-in matrix, but the firmware's matrix
    /// itself stays compiled in; macros travel alongside layers, since one
    /// upload has to leave the board self-consistent. Can throw
    /// `KeymapCompileError` for a token this build has no binary tag for, or
    /// a parameter that doesn't fit the wire format's one-byte fields.
    func compileForUpload() throws -> [UInt8] {
        try compileKeymap(document)
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

    /// The firmware's own ceiling, not an editor preference: `LayerEngine`'s
    /// `toggledLayers`/`momentaryCounts` are sized `count: 16` and
    /// `isLayerActive` rejects anything `>= 16`, so a device can only ever
    /// activate layers 0-15. Part of the firmware coupling this app tracks
    /// by hand (see CLAUDE.md) -- bump it only alongside the firmware.
    static let maxLayerCount = 16

    /// Highest layer index the palette's MO/TG chips may name: the last
    /// layer the document actually has, capped by `maxLayerCount` (a loaded
    /// file can legally hold more layers than the firmware can activate).
    /// Anything above this would emit an `mo:`/`tg:` token that can never
    /// fire, since the firmware's `getAction` only walks the layers it has.
    var maxAssignableLayerIndex: Int {
        min(document.layers.count, Self.maxLayerCount) - 1
    }

    func addLayer() {
        guard document.layers.count < Self.maxLayerCount else { return }
        document.layers.append(KeymapDocument.blankTransparentLayer(for: activeDesign))
        currentLayer = document.layers.count - 1
        isDirty = true
    }

    /// Removes the layer currently being edited. Deliberately just the
    /// selected-row case of `removeLayer(at:)` -- including its refusal to
    /// delete layer 0 -- so both entry points renumber `mo:`/`tg:`
    /// references identically instead of drifting apart.
    func removeCurrentLayer() {
        removeLayer(at: currentLayer)
    }

    /// The Layers list's per-row delete (hover trash glyph, confirmed via
    /// alert) -- unlike `removeCurrentLayer()`, this can remove a layer
    /// that isn't the one currently being edited. Layer 0 ("Base") is never
    /// deletable: the firmware always treats it as the present-by-default
    /// layer.
    func removeLayer(at index: Int) {
        guard document.layers.count > 1, index > 0, index < document.layers.count else { return }
        document.layers.remove(at: index)
        // Every mo:/tg: cell above `index` now names the wrong layer -- fix
        // the whole document before anything else looks at it.
        document.renumberLayerReferences(afterRemoving: index)
        // Layers after `index` shifted down by one -- follow the same
        // physical layer rather than silently landing on whatever now
        // occupies the old `currentLayer` slot. If `currentLayer` was the
        // one just removed, it's left pointing at whatever shifted into
        // that index (or clamped below if it was the last layer).
        if currentLayer > index {
            currentLayer -= 1
        }
        currentLayer = min(currentLayer, document.layers.count - 1)
        // Same shift for the palette's MO/TG stepper, so it keeps naming the
        // layer it named before rather than one that no longer exists.
        if pendingLayerIndex > index {
            pendingLayerIndex -= 1
        }
        clampPendingLayerIndex()
        isDirty = true
    }

    /// Pulls the palette's MO/TG stepper back into range whenever the
    /// document's layer count shrinks (delete, load, New) -- otherwise it
    /// keeps offering `mo:`/`tg:` chips for layers that aren't there.
    private func clampPendingLayerIndex() {
        pendingLayerIndex = max(0, min(pendingLayerIndex, maxAssignableLayerIndex))
    }

    func toggleSelection(_ token: ActionToken) {
        selectedToken = (selectedToken == token) ? nil : token
    }

    func setDrawerHeight(_ height: Double) {
        drawerHeight = height
        userDefaults.set(drawerHeight, forKey: drawerHeightDefaultsKey)
    }

    func setShowAdvanced(_ value: Bool) {
        showAdvanced = value
        userDefaults.set(value, forKey: showAdvancedDefaultsKey)
    }

    func setAppearanceMode(_ mode: AppearanceMode) {
        appearanceMode = mode
        userDefaults.set(mode.rawValue, forKey: appearanceModeDefaultsKey)
    }

    // MARK: - Macro capacity

    /// `deviceKey` for the USB (RP2040) transport. hidapi's device
    /// enumeration in `USBRawHIDTransport` doesn't read a per-board serial
    /// number, so every RP2040 board seen over USB shares this one bucket.
    static let usbDeviceKey = "usb"

    /// `deviceKey` for the BLE (ESP32-C6) transport, keyed by whatever name
    /// the peripheral advertised -- the only per-board signal
    /// `refreshDeviceStatus()` already surfaces. Falls back to a shared
    /// bucket if a name was never read.
    #if canImport(CoreBluetooth)
    var bleDeviceKey: String { "ble:\(blePeripheralName ?? "unknown")" }
    #endif

    /// Adopts a `CAPS` opcode (0x05) response from a connected board: the
    /// live meter switches to `.device` immediately, and the numbers are
    /// persisted under `deviceKey` so a later session with no board
    /// connected reports `.lastKnown` (see `init()`) instead of dropping
    /// back to `MacroCapacity.floor`. `deviceKey` is the best device
    /// identity this app currently has -- `"usb"` for the RP2040 transport
    /// (which exposes no per-board serial) and `"ble:<peripheral name>"`
    /// for BLE -- not a strict per-physical-board key, but distinguishes the
    /// port families that actually have different capacities.
    ///
    /// Takes an already-decoded report rather than a transport, so this
    /// half is reachable from a test without a real transport -- see
    /// `KeymapUploader.queryCapacity(using:)` in `DeviceTransport.swift` for
    /// the wire round trip that produces `report`, and `MacroCapacityTests`
    /// for why `sendToDevice()`-style guards never call a real transport
    /// from a test.
    func applyDeviceCapacity(_ report: DeviceCapacityReport, deviceKey: String) {
        let capacity = MacroCapacity(macroBytes: report.macroBytes, macroSlots: report.macroSlots)
        macroCapacity = capacity
        macroCapacitySource = .device
        if let data = try? JSONEncoder().encode(capacity) {
            userDefaults.set(data, forKey: macroCapacityDefaultsKey(forDeviceKey: deviceKey))
        }
        userDefaults.set(deviceKey, forKey: macroCapacityLastDeviceKeyDefaultsKey)
    }

    // MARK: - Key inspector

    /// Focuses the Key inspector on `(row, col)` -- called whenever a keycap
    /// is tapped, independent of the click-to-arm/click-to-place palette
    /// selection (`selectedToken`).
    func selectKey(row: Int, col: Int) {
        selectedKeyPosition = KeyPosition(row: row, col: col)
    }

    /// The Key inspector's "Reassign" button: commits whatever's currently
    /// armed from the palette onto the inspected key, then disarms it. A
    /// button-driven alternative to tapping the keycap directly.
    func reassignSelectedKey() {
        guard let position = selectedKeyPosition, let armed = selectedToken else { return }
        assign(armed, row: position.row, col: position.col)
        selectedToken = nil
    }

    /// The Key inspector's "Clear" button: sets the inspected key back to
    /// `.none`.
    func clearSelectedKey() {
        guard let position = selectedKeyPosition else { return }
        assign(.none, row: position.row, col: position.col)
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

    // MARK: - Macro editing

    var macroBudget: MacroBudget {
        MacroBudget(capacity: macroCapacity,
                    source: macroCapacitySource,
                    macros: document.macroList)
    }

    /// The macro currently open in the editor, if any. Named `currentMacro`
    /// rather than `openMacro` because a property and a method cannot share
    /// an identifier — `openMacro(id:)` below is the verb.
    var currentMacro: MacroDefinition? {
        guard let id = macroWorkspace.openMacroID else { return nil }
        return document.macroList.first { $0.id == id }
    }

    /// The name for `macro:<id>`, used by `KeyCapView` — the one token whose
    /// label isn't self-contained. Nil when the slot holds no macro, so the
    /// keycap can fall back to the token's own "M<id>".
    func macroName(for id: Int) -> String? {
        document.macroList.first { $0.id == id }?.name
    }

    func createMacro() {
        let macro = MacroDefinition(id: document.nextMacroID, name: "New macro", steps: [])
        document.macros = document.macroList + [macro]
        macroWorkspace = .editor(id: macro.id)
        selectedStepIndex = nil
        isDirty = true
    }

    /// No-op for an id with no macro -- a view should never call this with an
    /// id it didn't get from `document.macroList`, but landing in an editor
    /// for a macro that doesn't exist (where `currentMacro` then resolves to
    /// nil) is worse than silently doing nothing.
    func openMacro(id: Int) {
        guard let macro = document.macroList.first(where: { $0.id == id }) else { return }
        macroWorkspace = .editor(id: id)
        selectedStepIndex = macro.steps.isEmpty ? nil : 0
    }

    func closeMacro() {
        macroWorkspace = .library
        selectedStepIndex = nil
    }

    /// Closes the editor only when the macro being edited is the one that
    /// just vanished -- not on every deletion. Deleting a macro other than
    /// the one currently open must leave that editor alone.
    func deleteMacro(id: Int) {
        document.macros = document.macroList.filter { $0.id != id }
        if document.macroList.isEmpty { document.macros = nil }
        if macroWorkspace.openMacroID == id { closeMacro() }
        isDirty = true
    }

    func updateMacro(_ macro: MacroDefinition) {
        guard let index = document.macroList.firstIndex(where: { $0.id == macro.id }) else { return }
        var list = document.macroList
        list[index] = macro
        document.macros = list
        isDirty = true
    }

    /// Applies `transform` to the macro currently open, if any.
    private func mutateOpenMacro(_ transform: (inout MacroDefinition) -> Void) {
        guard var macro = currentMacro else { return }
        transform(&macro)
        updateMacro(macro)
    }

    func appendStep(_ step: MacroStep) {
        guard currentMacro != nil else { return }
        mutateOpenMacro { $0.steps.append(step) }
        selectedStepIndex = (currentMacro?.steps.count ?? 1) - 1
    }

    /// Inserts after the selected step, which is how a position is chosen
    /// without drag-and-drop. With nothing selected, appends.
    func insertStepAfterSelection(_ step: MacroStep) {
        guard let selected = selectedStepIndex, currentMacro != nil else {
            appendStep(step)
            return
        }
        let target = selected + 1
        mutateOpenMacro { $0.steps.insert(step, at: min(target, $0.steps.count)) }
        // Clamp against the post-mutation state, not the unclamped `target`
        // -- a stale `selectedStepIndex` (e.g. left over from a larger macro)
        // must not leave the selection pointing past the array's new end.
        let remaining = currentMacro?.steps.count ?? 0
        selectedStepIndex = remaining == 0 ? nil : min(target, remaining - 1)
    }

    func moveStep(from source: Int, to destination: Int) {
        guard let macro = currentMacro,
              macro.steps.indices.contains(source),
              macro.steps.indices.contains(destination)
        else { return }
        mutateOpenMacro {
            let step = $0.steps.remove(at: source)
            $0.steps.insert(step, at: destination)
        }
        selectedStepIndex = destination
    }

    func deleteStep(at index: Int) {
        guard let macro = currentMacro, macro.steps.indices.contains(index) else { return }
        mutateOpenMacro { $0.steps.remove(at: index) }
        let remaining = currentMacro?.steps.count ?? 0
        selectedStepIndex = remaining == 0 ? nil : min(index, remaining - 1)
    }
}
