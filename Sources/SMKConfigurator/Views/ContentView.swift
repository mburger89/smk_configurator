import Foundation
import SwiftCrossUI

struct ContentView: View {
    @Environment(EditorState.self) var editor
    @Environment(\.chooseFile) var chooseFile
    @Environment(\.chooseFileSaveDestination) var chooseFileSaveDestination
    @Environment(\.presentAlert) var presentAlert

    @State var isEditingDesign = false
    @State var designBuilderSeed = KeyboardDesign.blank()
    @State var designBeingEdited: KeyboardDesign? = nil

    @State var isEditingTheme = false
    @State var themeBuilderSeed = KeyboardTheme.blank()
    @State var themeBeingEdited: KeyboardTheme? = nil

    var body: some View {
        VStack(spacing: 10) {
            toolbar
            designBar
            themeBar
            Divider()
            HStack(spacing: 10) {
                LayerTabsView()
                Divider()
                VStack(spacing: 10) {
                    ScrollView {
                        KeyboardBoardView()
                    }
                    PaletteDrawerView()
                }
            }
            .background(editor.activeTheme.background.color)
        }
        .padding(10)
        .onChange(of: editor.loadError) {
            guard let message = editor.loadError else { return }
            Task {
                await presentAlert(message)
                editor.loadError = nil
            }
        }
        .sheet(isPresented: $isEditingDesign) {
            DesignBuilderView(
                isPresented: $isEditingDesign,
                draft: designBuilderSeed,
                editingExisting: designBeingEdited
            )
        }
        .sheet(isPresented: $isEditingTheme) {
            ThemeBuilderView(
                isPresented: $isEditingTheme,
                draft: themeBuilderSeed,
                editingExisting: themeBeingEdited
            )
        }
    }

    private var themeBar: some View {
        HStack(spacing: 10) {
            Menu("Theme: \(editor.activeTheme.name)") {
                ForEach(editor.availableThemes) { theme in
                    Button(theme.name) {
                        editor.selectTheme(theme)
                    }
                }
            }
            Button("New Theme…") {
                themeBuilderSeed = .blank()
                themeBeingEdited = nil
                isEditingTheme = true
            }
            Button("Edit Theme…") {
                themeBuilderSeed = editor.activeTheme
                themeBeingEdited = editor.activeTheme
                isEditingTheme = true
            }
            Button("Duplicate…") {
                var copy = editor.activeTheme
                copy.name = "\(editor.activeTheme.name) copy"
                themeBuilderSeed = copy
                themeBeingEdited = nil
                isEditingTheme = true
            }
            Button("Import…") {
                Task {
                    guard
                        let url = await chooseFile(
                            title: "Import theme JSON",
                            allowSelectingFiles: true
                        )
                    else { return }
                    editor.importTheme(from: url)
                }
            }
            Button("Export…") {
                Task {
                    guard
                        let url = await chooseFileSaveDestination(
                            title: "Export theme",
                            defaultFileName: "\(editor.activeTheme.name).json"
                        )
                    else { return }
                    editor.exportTheme(editor.activeTheme, to: url)
                }
            }
        }
    }

    private var designBar: some View {
        HStack(spacing: 10) {
            Menu("Design: \(editor.activeDesign.name)") {
                ForEach(editor.availableDesigns) { design in
                    Button(design.name) {
                        editor.selectDesign(design)
                    }
                }
            }
            Button("New Design…") {
                designBuilderSeed = .blank()
                designBeingEdited = nil
                isEditingDesign = true
            }
            Button("Edit Design…") {
                designBuilderSeed = editor.activeDesign
                designBeingEdited = editor.activeDesign
                isEditingDesign = true
            }
            Button("Duplicate…") {
                var copy = editor.activeDesign
                copy.name = "\(editor.activeDesign.name) copy"
                designBuilderSeed = copy
                designBeingEdited = nil
                isEditingDesign = true
            }
            Button("Import…") {
                Task {
                    guard
                        let url = await chooseFile(
                            title: "Import design JSON",
                            allowSelectingFiles: true
                        )
                    else { return }
                    editor.importDesign(from: url)
                }
            }
            Button("Export…") {
                Task {
                    guard
                        let url = await chooseFileSaveDestination(
                            title: "Export design",
                            defaultFileName: "\(editor.activeDesign.name).json"
                        )
                    else { return }
                    editor.exportDesign(editor.activeDesign, to: url)
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button("New") {
                editor.newDocument()
            }
            Button("Open…") {
                Task {
                    guard
                        let url = await chooseFile(
                            title: "Open keymap.json",
                            initialDirectory: defaultKeymapURL.deletingLastPathComponent()
                        )
                    else { return }
                    editor.load(from: url)
                }
            }
            Button("Save") {
                Task {
                    if let url = editor.fileURL {
                        editor.save(to: url)
                    } else {
                        await saveAs()
                    }
                }
            }
            Button("Save As…") {
                Task { await saveAs() }
            }
            Button(editor.isSendingToDevice ? "Sending…" : "Send to Device") {
                editor.sendToDevice()
            }
            .disabled(editor.isSendingToDevice)
            Text(editor.fileURL?.path ?? "(unsaved)")
                .foregroundColor(.gray)
            if editor.isDirty {
                Text("•").foregroundColor(.orange)
            }
            Spacer()
            if editor.selectedToken != nil {
                Text("Selected: \(editor.selectedToken?.displayLabel ?? "")")
                    .foregroundColor(.blue)
                Button("Clear") {
                    editor.selectedToken = nil
                }
            }
        }
    }

    private func saveAs() async {
        guard
            let url = await chooseFileSaveDestination(
                title: "Save keymap.json",
                initialDirectory: defaultKeymapURL.deletingLastPathComponent(),
                defaultFileName: "keymap.json"
            )
        else { return }
        editor.save(to: url)
    }
}
