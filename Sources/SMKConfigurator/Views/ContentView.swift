import Foundation
import SwiftCrossUI

/// The app's root view: titlebar -> 4-pane body (icon rail / list / main /
/// inspector, driven by `editor.railMode`) -> status bar. See
/// `design_handoff_1c_power_grouped_list/README.md` for the full layout
/// spec this recreates.
///
/// Design/theme editing used to happen in modal sheets (`DesignBuilderView`/
/// `ThemeBuilderView`); this redesign moves that editing inline into the
/// DSN/THM panes instead, so `ContentView` now owns a small "draft"
/// workspace for each -- a scratch copy that mirrors whatever design/theme
/// is selected until explicitly saved, mirroring the old sheets'
/// edit-then-Save/Cancel flow without the modal.
struct ContentView: View {
    @Environment(EditorState.self) var editor
    @Environment(\.chooseFile) var chooseFile
    @Environment(\.chooseFileSaveDestination) var chooseFileSaveDestination
    @Environment(\.presentAlert) var presentAlert
    @Environment(\.colorScheme) private var colorScheme
    private var chrome: Chrome { Chrome(scheme: colorScheme) }

    @State var designDraft: KeyboardDesign = .blank()
    /// `nil` while the draft is an unsaved "+ New Design…"; the design
    /// being replaced otherwise (needed so Delete doesn't leave old files
    /// behind, and so a fresh draft can't be deleted).
    @State var editingDesignOriginal: KeyboardDesign? = nil
    @State var selectedDesignCell: DesignGridPosition? = nil

    @State var themeDraft: KeyboardTheme = .blank()
    @State var editingThemeOriginal: KeyboardTheme? = nil

    /// Everything `body` stacks above and below the four-pane row: titlebar
    /// (50) + the top divider and the one above the status bar (~3) +
    /// status bar (26).
    private static let chromeHeight: Double = 79

    /// The window floor. KEY mode's Main content column is the tallest of
    /// the four, so it sets the bound: chrome plus what that column needs
    /// with the board at `boardMinHeight` and the palette drawer squeezed to
    /// its own floor. Kept deliberately under the ~730pt of usable height a
    /// 1366x768 laptop has -- a floor taller than the screen leaves the
    /// status bar unreachable with no way to shrink the window. See
    /// `PaletteDrawerView.maxHeight` for why the drawer can shrink again.
    static let minWindowHeight: Double = chromeHeight + KeyMainContentView.minContentHeight

    /// Launch height: enough for the palette to show every section without
    /// scrolling. Larger than `minWindowHeight` on purpose -- the OS clamps
    /// it down to whatever the display can fit, and the window stays
    /// resizable from there.
    static let idealWindowHeight: Double = chromeHeight + KeyMainContentView.idealContentHeight

    var body: some View {
        VStack(spacing: 0) {
            TitlebarView()
            chrome.divider.frame(height: 2)
            HStack(spacing: 0) {
                IconRailView(mode: railModeBinding)
                Divider()
                listColumn
                Divider()
                mainContent
                Divider()
                inspectorColumn
            }
            Divider()
            StatusBarView()
        }
        .frame(minWidth: 1440, minHeight: Self.minWindowHeight)
        .onAppear {
            designDraft = editor.activeDesign
            editingDesignOriginal = editor.activeDesign
            themeDraft = editor.activeTheme
            editingThemeOriginal = editor.activeTheme
        }
        .onChange(of: editor.loadError) {
            guard let message = editor.loadError else { return }
            Task {
                await presentAlert(message)
                editor.loadError = nil
            }
        }
    }

    private var railModeBinding: Binding<RailMode> {
        Binding(get: { editor.railMode }, set: { editor.railMode = $0 })
    }

    @ViewBuilder
    private var listColumn: some View {
        switch editor.railMode {
        case .key:
            KeyListColumnView(selectDesign: loadDesignDraft, selectTheme: loadThemeDraft)
        case .designs:
            DesignListColumnView(draft: $designDraft, selectDesign: loadDesignDraft, newDesign: newDesignDraft)
        case .themes:
            ThemeListColumnView(draft: $themeDraft, selectTheme: loadThemeDraft, newTheme: newThemeDraft)
        case .device:
            DeviceListColumnView()
        case .macros:
            EmptyView()
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch editor.railMode {
        case .key:
            KeyMainContentView()
        case .designs:
            DesignGridEditorView(draft: $designDraft, selectedCell: $selectedDesignCell)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .themes:
            ThemeMainContentView(draft: themeDraft)
        case .device:
            DeviceMainContentView()
        case .macros:
            EmptyView()
        }
    }

    @ViewBuilder
    private var inspectorColumn: some View {
        switch editor.railMode {
        case .key:
            KeyInspectorView()
        case .designs:
            DesignInspectorView(
                draft: designDraft,
                isExistingDesign: editingDesignOriginal != nil,
                save: saveDesignDraft,
                duplicate: duplicateDesignDraft,
                delete: deleteDesignDraft
            )
        case .themes:
            ThemeInspectorView(
                draft: themeDraft,
                save: saveThemeDraft,
                duplicate: duplicateThemeDraft,
                importTheme: importThemeDraft,
                exportTheme: exportThemeDraft
            )
        case .device:
            DeviceInspectorView()
        case .macros:
            EmptyView()
        }
    }

    // MARK: - Design workspace

    private func loadDesignDraft(_ design: KeyboardDesign) {
        editor.selectDesign(design)
        designDraft = design
        editingDesignOriginal = design
        selectedDesignCell = nil
    }

    private func newDesignDraft() {
        designDraft = .blank()
        editingDesignOriginal = nil
        selectedDesignCell = nil
    }

    private func saveDesignDraft() {
        editor.saveDesign(designDraft)
        editingDesignOriginal = designDraft
    }

    private func duplicateDesignDraft() {
        editor.duplicateDesign(designDraft, as: "\(designDraft.name) copy")
        designDraft = editor.activeDesign
        editingDesignOriginal = editor.activeDesign
    }

    private func deleteDesignDraft() {
        if let editingDesignOriginal {
            editor.deleteDesign(editingDesignOriginal)
        }
        designDraft = editor.activeDesign
        editingDesignOriginal = editor.activeDesign
        selectedDesignCell = nil
    }

    // MARK: - Theme workspace

    private func loadThemeDraft(_ theme: KeyboardTheme) {
        editor.selectTheme(theme)
        themeDraft = theme
        editingThemeOriginal = theme
    }

    private func newThemeDraft() {
        themeDraft = .blank()
        editingThemeOriginal = nil
    }

    private func saveThemeDraft() {
        editor.saveTheme(themeDraft)
        editingThemeOriginal = themeDraft
    }

    private func duplicateThemeDraft() {
        editor.duplicateTheme(themeDraft, as: "\(themeDraft.name) copy")
        themeDraft = editor.activeTheme
        editingThemeOriginal = editor.activeTheme
    }

    private func importThemeDraft() {
        Task {
            guard
                let url = await chooseFile(title: "Import theme JSON", allowSelectingFiles: true)
            else { return }
            editor.importTheme(from: url)
            themeDraft = editor.activeTheme
            editingThemeOriginal = editor.activeTheme
        }
    }

    private func exportThemeDraft() {
        Task {
            guard
                let url = await chooseFileSaveDestination(
                    title: "Export theme",
                    defaultFileName: "\(themeDraft.name).json"
                )
            else { return }
            editor.exportTheme(themeDraft, to: url)
        }
    }
}
