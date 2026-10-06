import MetalUI

// DSN mode's list column and inspector (port plan §1.6). The grid editor is
// `DesignGridEditorView`.

/// DSN rail mode's list column: the Designs list (KEY mode's rows), a
/// "+ New Design…" link, and the draft's matrix GPIO wiring.
struct DesignListColumnView: Component {
    let editor: EditorState
    @Binding var draft: KeyboardDesign
    let selectDesign: @MainActor (KeyboardDesign) -> Void
    let newDesign: @MainActor () -> Void

    var content: some ElementGroup {
        pane {
            ListColumn {
                ListSection {
                    SectionHeader(title: "Designs")
                    for design in editor.availableDesigns {
                        DesignRow(design: design, isSelected: editor.activeDesign.id == design.id) { [selectDesign] in
                            selectDesign(design)
                        }
                    }
                    LinkButton(label: "+ New Design…", action: newDesign)
                }
                ListSection(spacing: 6) {
                    SectionHeader(title: "Matrix GPIO")
                    Text("Rows: " + draft.matrix.rows.map(String.init).joined(separator: ", "))
                        .font(.system(size: 11))
                        .foregroundColor(Chrome.textSecondary)
                    Text("Cols: " + draft.matrix.cols.map(String.init).joined(separator: ", "))
                        .font(.system(size: 11))
                        .foregroundColor(Chrome.textSecondary)
                    Toggle("Columns are driven", isOn: colsAreDriven)
                }
            }
        }
    }

    private var colsAreDriven: Binding<Bool> {
        let draft = $draft
        return Binding(
            get: { draft.wrappedValue.matrix.colsAreDriven != 0 },
            set: { draft.wrappedValue.matrix.colsAreDriven = $0 ? 1 : 0 }
        )
    }
}

/// DSN rail mode's inspector: Save, Duplicate and Delete for the design open
/// in the grid editor. Delete is disabled for an unsaved "+ New Design…".
struct DesignInspectorView: Component {
    let draft: KeyboardDesign
    let isExistingDesign: Bool
    let save: @MainActor () -> Void
    let duplicate: @MainActor () -> Void
    let delete: @MainActor () -> Void

    var content: some ElementGroup {
        pane {
            InspectorColumn {
                InspectorHeading(title: "Design actions",
                                 subtitle: "\(draft.rowCount) rows · \(draft.colCount) cols · \(draft.name) matrix")
                Divider()
                InspectorButton(label: "Save Design", isPrimary: true, action: save)
                InspectorButton(label: "Duplicate…", action: duplicate)
                InspectorButton(label: "Delete", isDestructive: true, isEnabled: isExistingDesign, action: delete)
            }
        }
    }
}
