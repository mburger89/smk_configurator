import MetalUI

/// One row in the macro's step list: ▲ ▼ reorder buttons, the step card (index,
/// type badge, payload summary, trailing metadata; a click selects it), and a
/// trailing ✕ delete. The inspector's repeat-block editor reuses it for the
/// steps inside a block.
///
/// Every control is a real `Button`. The previous build had to keep ▲ ▼ and ✕
/// as siblings of a hand-built tap target (port plan §2.2 W1, W9); here they
/// are simply three buttons in one row.
struct MacroStepRowView: Component {
    let step: MacroStep
    let index: Int
    let isSelected: Bool
    let onSelect: @MainActor () -> Void
    let onMoveUp: @MainActor () -> Void
    let onMoveDown: @MainActor () -> Void
    let onDelete: @MainActor () -> Void

    var content: some ElementGroup {
        Row(gap: Pixels(12)) {
            Column(gap: Pixels(2)) {
                arrow("▲", help: "Move up", action: onMoveUp)
                arrow("▼", help: "Move down", action: onMoveDown)
            }
            .alignItems(.center)
            .frame(width: Pixels(11))
            card
            Button(action: onDelete) {
                Text("✕")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Chrome.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Delete this step")
        }
        .alignItems(.center)
        .frame(maxWidth: Pixels(.infinity))
    }

    private var card: some Element {
        Button(action: onSelect) {
            Row(gap: Pixels(12)) {
                Text("\(index + 1)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Chrome.textTertiary)
                    .frame(width: Pixels(14), alignment: .leading)
                Text(step.typeCode)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Chrome.textSecondary)
                    .frame(width: Pixels(30), height: Pixels(18))
                    .background(Chrome.chipBackground)
                    .cornerRadius(Pixels(4))
                // One line each: in the inspector's narrow repeat-block list
                // the metadata otherwise wraps a letter at a time.
                Text(step.payloadSummary)
                    .font(.system(size: 12))
                    .foregroundColor(Chrome.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text(step.metadataLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Chrome.textTertiary)
                    .lineLimit(1)
            }
            .alignItems(.center)
            .padding(Insets.symmetric(horizontal: 13, vertical: 10))
            .frame(maxWidth: Pixels(.infinity), alignment: .leading)
        }
        .buttonStyle(.plain)
        .background(isSelected ? Chrome.accentWash : Chrome.column)
        .cornerRadius(Pixels(7))
        .border(isSelected ? Chrome.accent : Chrome.dividerLight, width: Pixels(1))
    }

    private func arrow(_ glyph: String, help: String, action: @escaping @MainActor () -> Void) -> some Element {
        Button(action: action) {
            Text(glyph)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(Chrome.textSecondary)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
