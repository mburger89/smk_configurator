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

    @State var designDraft: KeyboardDesign = .blank()
    /// `nil` while the draft is an unsaved "+ New Design…"; the design
    /// being replaced otherwise (needed so Delete doesn't leave old files
    /// behind, and so a fresh draft can't be deleted).
    @State var editingDesignOriginal: KeyboardDesign? = nil
    @State var selectedDesignCell: DesignGridPosition? = nil

    @State var themeDraft: KeyboardTheme = .blank()
    @State var editingThemeOriginal: KeyboardTheme? = nil

    var body: some View {
        VStack(spacing: 0) {
            TitlebarView()
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
        .frame(minWidth: 1440, minHeight: 900)
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
