import MetalUI

// THM mode (port plan §1.7): the list column with the draft's colour roles,
// the live preview, and the inspector.

/// THM rail mode's list column: the Themes list (KEY mode's rows), a
/// "+ New Theme…" link, and the eight editable colour roles of the theme open
/// in the draft.
struct ThemeListColumnView: Component {
    let editor: EditorState
    @Binding var draft: KeyboardTheme
    let selectTheme: @MainActor (KeyboardTheme) -> Void
    let newTheme: @MainActor () -> Void

    var content: some ElementGroup {
        pane {
            ListColumn {
                ListSection {
                    SectionHeader(title: "Themes")
                    for theme in editor.availableThemes {
                        ThemeRow(theme: theme, isSelected: editor.activeTheme.id == theme.id) { [selectTheme] in
                            selectTheme(theme)
                        }
                    }
                    LinkButton(label: "+ New Theme…", action: newTheme)
                }
                ListSection(spacing: 8) {
                    SectionHeader(title: "Color Roles")
                    for role in ThemeRole.allCases {
                        ThemeSwatchField(label: role.label, color: $draft[dynamicMember: role.keyPath])
                    }
                }
            }
        }
    }
}

/// THM rail mode's main content: KEY mode's board, drawn live with the draft
/// theme instead of `editor.activeTheme`, read-only.
struct ThemeMainContentView: Component {
    let editor: EditorState
    let draft: KeyboardTheme

    var content: some ElementGroup {
        pane {
            Column(gap: Pixels(10)) {
                ScrollView(.vertical) {
                    Column {
                        KeyboardBoardView(editor: editor, theme: draft, interactive: false)
                    }
                    .alignItems(.center)
                }
                .frame(maxWidth: Pixels(.infinity), minHeight: Pixels(0),
                       maxHeight: Pixels(KeyboardBoardView.naturalHeight(of: editor.activeDesign)))
                Text("Live preview — updates as color roles change")
                    .font(.system(size: 11))
                    .foregroundColor(Chrome.textTertiary)
            }
            .alignItems(.stretch)
            .padding(Pixels(20))
            .frame(maxWidth: Pixels(.infinity), maxHeight: Pixels(.infinity))
            .background(Chrome.canvas)
        }
    }
}

/// THM rail mode's inspector: Save, Duplicate, Import and Export for the
/// theme open in the draft. Import and Export go through MetalUI's file
/// dialogs (`ContentView.importThemeDraft`/`exportThemeDraft`).
struct ThemeInspectorView: Component {
    let draft: KeyboardTheme
    let save: @MainActor () -> Void
    let duplicate: @MainActor () -> Void
    let importTheme: @MainActor () -> Void
    let exportTheme: @MainActor () -> Void

    var content: some ElementGroup {
        pane {
            InspectorColumn {
                InspectorHeading(title: "Theme actions", subtitle: "Editing: \(draft.name)")
                Divider()
                InspectorButton(label: "Save Theme", isPrimary: true, action: save)
                InspectorButton(label: "Duplicate…", action: duplicate)
                InspectorButton(label: "Import…", action: importTheme)
                InspectorButton(label: "Export…", action: exportTheme)
            }
        }
    }
}
