import Foundation
import MetalUI

/// The window's root element. A lifecycle scope cannot be a window's root
/// (MetalUI divergence 120), so `ContentView` -- which carries `onAppear`,
/// `onChange` and the load-error alert -- sits inside a plain `Column`.
@MainActor
func rootView(editor: EditorState) -> some Element {
    Column {
        ContentView(editor: editor)
    }
    .frame(maxWidth: Pixels(.infinity), maxHeight: Pixels(.infinity))
}

/// The app's shell: the 4-pane body (icon rail / list / main / inspector,
/// driven by `editor.railMode`) over the status bar. See
/// `design_handoff_1c_power_grouped_list/README.md` for the layout spec this
/// recreates. The previous build's titlebar strip is gone (port plan §2.2 W8):
/// its file actions are the File menu and Advanced Mode is a View menu item
/// (`AppCommands.swift`). On Linux and Windows, where SDL draws no menu bar,
/// the same items are a toolbar MetalUI draws as a strip across the top
/// (`platformToolbar`, `PlatformToolbar.swift`; compiled out on macOS).
///
/// Design/theme editing happens inline in the DSN/THM panes, so `ContentView`
/// owns a small "draft" workspace for each -- a scratch copy that mirrors
/// whatever design/theme is selected until explicitly saved.
struct ContentView: Component {
    let editor: EditorState

    @Environment(\.fileDialogs) var dialogs
    /// Picks the toolbar's icon files (Linux/Windows only, `platformToolbar`).
    @Environment(\.colorScheme) var colorScheme

    @State var designDraft: KeyboardDesign = .blank()
    /// `nil` while the draft is an unsaved "+ New Design…"; the design
    /// being replaced otherwise (needed so Delete doesn't leave old files
    /// behind, and so a fresh draft can't be deleted).
    @State var editingDesignOriginal: KeyboardDesign? = nil
    @State var selectedDesignCell: DesignGridPosition? = nil

    @State var themeDraft: KeyboardTheme = .blank()
    @State var editingThemeOriginal: KeyboardTheme? = nil

    /// Whether the load-error alert is up, and the message it shows (kept
    /// apart from `editor.loadError`, which clears when the alert goes).
    @State var showingLoadError = false
    @State var loadErrorMessage = ""

    /// Whether an ADD STEP row is being dragged over the "Add a step" card,
    /// written by its drop destination's `isTargeted` callback (input).
    @State var addStepCardTargeted = false

    var content: some ElementGroup {
        Column {
            paneRow
            Divider()
            StatusBarView(editor: editor)
        }
        .frame(maxWidth: Pixels(.infinity), maxHeight: Pixels(.infinity))
        .background(Chrome.canvas)
        .preferredColorScheme(editor.appearanceMode.colorScheme)
        .onAppear {
            designDraft = editor.activeDesign
            editingDesignOriginal = editor.activeDesign
            themeDraft = editor.activeTheme
            editingThemeOriginal = editor.activeTheme
        }
        .onChange(of: editor.loadError) {
            guard let message = editor.loadError else { return }
            loadErrorMessage = message
            showingLoadError = true
        }
        .alert(loadErrorMessage, isPresented: loadErrorBinding) {
            Button("OK") {}
        }
        .platformToolbar(editor: editor, dialogs: dialogs, colorScheme: colorScheme)
    }

    /// Any dismissal clears the model's error, so the same error raised again
    /// is a change `onChange` sees.
    private var loadErrorBinding: Binding<Bool> {
        let presented = $showingLoadError
        let editor = editor
        return Binding(get: { presented.wrappedValue },
                       set: { isPresented in
                           presented.wrappedValue = isPresented
                           if !isPresented { editor.loadError = nil }
                       })
    }

    /// The macro library takes the whole body: no list or inspector column.
    private var hasSideColumns: Bool {
        !(editor.railMode == .macros && editor.macroWorkspace == .library)
    }

    private var paneRow: some Element {
        Row {
            IconRailView(editor: editor)
            Divider()
            if hasSideColumns {
                listColumn
                Divider()
            }
            mainContent
            if hasSideColumns {
                Divider()
                inspectorColumn
            }
        }
        .frame(maxWidth: Pixels(.infinity), maxHeight: Pixels(.infinity))
    }

    @ElementBuilder
    private var listColumn: some ElementGroup {
        switch editor.railMode {
        case .key:
            KeyListColumnView(editor: editor, selectDesign: loadDesignDraft, selectTheme: loadThemeDraft)
        case .designs:
            DesignListColumnView(editor: editor, draft: $designDraft, selectDesign: loadDesignDraft,
                                 newDesign: newDesignDraft)
        case .themes:
            ThemeListColumnView(editor: editor, draft: $themeDraft, selectTheme: loadThemeDraft,
                                newTheme: newThemeDraft)
        case .device:
            DeviceListColumnView(editor: editor)
        case .macros:
            MacroStepPaletteView(editor: editor)
        }
    }

    @ElementBuilder
    private var mainContent: some ElementGroup {
        switch editor.railMode {
        case .key:
            KeyMainContentView(editor: editor)
        case .designs:
            DesignGridEditorView(draft: $designDraft, selectedCell: $selectedDesignCell)
        case .themes:
            ThemeMainContentView(editor: editor, draft: themeDraft)
        case .device:
            DeviceMainContentView(editor: editor)
        case .macros:
            switch editor.macroWorkspace {
            case .library:
                MacroLibraryView(editor: editor)
            case .editor:
                macroEditorContent
            }
        }
    }

    /// MACROS mode's step editor Main content: the canvas header, a
    /// reorder/delete hint above the step list, the sequence itself, and the
    /// add-step card. An empty canvas when `editor.currentMacro` is nil, which
    /// shouldn't happen while `macroWorkspace` is `.editor` but is safer than
    /// force-unwrapping.
    @ElementBuilder
    private var macroEditorContent: some ElementGroup {
        if let macro = editor.currentMacro {
            Column {
                MacroCanvasHeaderView(editor: editor)
                Text("Select a step to reorder or delete")
                    .font(.system(size: 11))
                    .foregroundColor(Chrome.textTertiary)
                    .padding(Insets.edges(leading: 16, bottom: 8, trailing: 16))
                ScrollView(.vertical) {
                    Column(gap: Pixels(6)) {
                        for index in macro.steps.indices {
                            stepRow(macro.steps[index], at: index)
                        }
                    }
                    .alignItems(.stretch)
                    .padding(Insets.edges(leading: 16, bottom: 12, trailing: 16))
                }
                .frame(maxWidth: Pixels(.infinity), minHeight: Pixels(0), maxHeight: Pixels(.infinity))
                addStepCard
            }
            .alignItems(.flexStart)
            .frame(maxWidth: Pixels(.infinity), maxHeight: Pixels(.infinity), alignment: .topLeading)
            .background(Chrome.canvas)
        } else {
            Box()
                .frame(maxWidth: Pixels(.infinity), maxHeight: Pixels(.infinity))
                .background(Chrome.canvas)
        }
    }

    private func stepRow(_ step: MacroStep, at index: Int) -> MacroStepRowView {
        let editor = editor
        return MacroStepRowView(
            step: step,
            index: index,
            isSelected: editor.selectedStepIndex == index,
            onSelect: { editor.selectedStepIndex = index },
            onMoveUp: { editor.moveStep(from: index, to: index - 1) },
            onMoveDown: { editor.moveStep(from: index, to: index + 1) },
            onDelete: { editor.deleteStep(at: index) }
        )
    }

    /// Appends a fresh keystroke step at the very end, independent of the
    /// current selection, complementing the palette's insert-after-selection
    /// placement. It is also the drop zone for an ADD STEP row dragged from the
    /// palette column (`MacroStepTypeRow`, `MacroStepDrop`): the dropped type is
    /// appended, and the card wears an accent ring while one is over it. The
    /// previous build offered the click as a substitute for this drop (port
    /// plan §2.2 W6).
    private var addStepCard: some Element {
        let editor = editor
        let targeted = $addStepCardTargeted
        // The card sits in a `Box` so the outer padding is a margin: padding
        // on the button itself would sit inside its fill and hit area.
        return Box {
            card(editor: editor, targeted: targeted)
        }
        .padding(Insets.edges(leading: 16, bottom: 12, trailing: 16))
    }

    private func card(editor: EditorState, targeted: Binding<Bool>) -> some Element {
        Button {
            editor.appendStep(MacroStepType.keystroke.makeStep())
        } label: {
            Text("Add a step")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Chrome.textPrimary)
                .frame(maxWidth: Pixels(.infinity), minHeight: Pixels(44), maxHeight: Pixels(44))
        }
        .buttonStyle(.plain)
        .background(Chrome.pillBackground.opacity(0.6))
        .cornerRadius(Pixels(8))
        .border(addStepCardTargeted ? Chrome.accent : Color.clear, width: Pixels(2))
        .help("Click to append a keystroke, or drop a step type here to append it")
        .dropDestination(for: String.self, action: { items, _ in
            guard let type = MacroStepDrop.type(from: items) else { return false }
            editor.appendStep(type.makeStep())
            return true
        }, isTargeted: { targeted.wrappedValue = $0 })
    }

    @ElementBuilder
    private var inspectorColumn: some ElementGroup {
        switch editor.railMode {
        case .key:
            KeyInspectorView(editor: editor)
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
            DeviceInspectorView(editor: editor)
        case .macros:
            MacroInspectorView(editor: editor)
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

    /// The open panel ("Import theme JSON" in the previous build -- MetalUI's
    /// dialogs take no title, gap MG-5), then the imported theme becomes the
    /// draft.
    private func importThemeDraft() {
        let dialogs = dialogs
        let editor = editor
        let themeDraft = $themeDraft
        let editingThemeOriginal = $editingThemeOriginal
        Task { @MainActor in
            guard let url = await KeymapFileActions.chooseFile(editor: editor, dialogs: dialogs) else { return }
            editor.importTheme(from: url)
            themeDraft.wrappedValue = editor.activeTheme
            editingThemeOriginal.wrappedValue = editor.activeTheme
        }
    }

    private func exportThemeDraft() {
        let dialogs = dialogs
        let editor = editor
        let theme = themeDraft
        Task { @MainActor in
            guard let url = await KeymapFileActions.chooseDestination(
                editor: editor, dialogs: dialogs, defaultFilename: "\(theme.name).json"
            ) else { return }
            editor.exportTheme(theme, to: url)
        }
    }
}
