import SwiftCrossUI

/// THM rail mode's List column: the Themes list (dot + name, same selection
/// styling as KEY mode) plus a "+ New Theme…" link and the 8 editable
/// color-role rows for whichever theme is open in the draft.
struct ThemeListColumnView: View {
    @Environment(EditorState.self) var editor
    @Environment(\.colorScheme) private var colorScheme
    private var chrome: Chrome { Chrome(scheme: colorScheme) }
    @Binding var draft: KeyboardTheme
    var selectTheme: (KeyboardTheme) -> Void
    var newTheme: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionHeader(title: "Themes")
                    ForEach(editor.availableThemes) { theme in
                        themeRow(theme)
                    }
                    Text("+ New Theme…")
                        .font(.system(size: 13))
                        .foregroundColor(chrome.accent)
                        .padding(EdgeInsets(top: 4, bottom: 0, leading: 8, trailing: 0))
                        .onTapGesture { newTheme() }
                }
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Color Roles")
                    ThemeSwatchField(label: "Background", color: bind(\.background))
                    ThemeSwatchField(label: "Key background", color: bind(\.keyBackground))
                    ThemeSwatchField(label: "Font color", color: bind(\.keyText))
                    ThemeSwatchField(label: "Modifier keys", color: bind(\.modifierBackground))
                    ThemeSwatchField(label: "Layer keys", color: bind(\.layerBackground))
                    ThemeSwatchField(label: "Special keys", color: bind(\.specialBackground))
                    ThemeSwatchField(label: "Empty keys", color: bind(\.emptyBackground))
                    ThemeSwatchField(label: "Accent / selection", color: bind(\.accent))
                }
            }
            .padding(EdgeInsets(top: 12, bottom: 12, leading: 10, trailing: 10))
        }
        .frame(width: 260)
        .frame(maxHeight: .infinity)
        .background(chrome.column)
    }

    private func themeRow(_ theme: KeyboardTheme) -> some View {
        let isSelected = editor.activeTheme.id == theme.id
        return ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? chrome.accentWash : Color.clear)
            HStack(spacing: 8) {
                Circle().fill(theme.accent.color).frame(width: 10, height: 10)
                Text(theme.name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? chrome.accent : chrome.textPrimary)
                Spacer()
            }
            .padding(EdgeInsets(top: 6, bottom: 6, leading: 8, trailing: 8))
        }
        .onTapGesture { selectTheme(theme) }
    }

    private func bind(_ keyPath: WritableKeyPath<KeyboardTheme, ThemeColor>) -> Binding<ThemeColor> {
        Binding(get: { draft[keyPath: keyPath] }, set: { draft[keyPath: keyPath] = $0 })
    }
}

/// THM rail mode's Main content: the same board renderer as KEY mode,
/// re-rendered live with the draft theme instead of `editor.activeTheme`,
/// read-only.
struct ThemeMainContentView: View {
    var draft: KeyboardTheme

    @Environment(\.colorScheme) private var colorScheme
    private var chrome: Chrome { Chrome(scheme: colorScheme) }

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            ScrollView {
                KeyboardBoardView(theme: draft, interactive: false)
                    .background(draft.background.color)
                    .cornerRadius(10)
            }
            Text("Live preview — updates as color roles change")
                .font(.system(size: 11))
                .foregroundColor(chrome.textTertiary)
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(chrome.canvas)
    }
}

/// THM rail mode's Inspector: Save/Duplicate/Import/Export for the theme
/// currently open in the draft.
struct ThemeInspectorView: View {
    var draft: KeyboardTheme
    var save: () -> Void
    var duplicate: () -> Void
    var importTheme: () -> Void
    var exportTheme: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var chrome: Chrome { Chrome(scheme: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Theme actions")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(chrome.textPrimary)
            Text("Editing: \(draft.name)")
                .font(.system(size: 12))
                .foregroundColor(chrome.textSecondary)
            Divider()
            InspectorButton(label: "Save Theme", isPrimary: true, action: save)
            InspectorButton(label: "Duplicate…", action: duplicate)
            InspectorButton(label: "Import…", action: importTheme)
            InspectorButton(label: "Export…", action: exportTheme)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 300)
        .frame(maxHeight: .infinity)
        .background(chrome.column)
    }
}
