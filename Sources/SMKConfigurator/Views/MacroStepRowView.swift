import MetalUI

/// One step in the step editor's list: ▲ ▼, the step card, ✕ -- a placeholder
/// until lane 3 of the port (plan §1.10). Final name and initialiser; clicking
/// it already selects the step.
struct MacroStepRowView: Component {
    let step: MacroStep
    let index: Int
    let isSelected: Bool
    let onSelect: @MainActor () -> Void
    let onMoveUp: @MainActor () -> Void
    let onMoveDown: @MainActor () -> Void
    let onDelete: @MainActor () -> Void

    var content: some ElementGroup {
        Text("\(index + 1). step row — not yet ported")
            .font(.system(size: 12))
            .foregroundColor(Chrome.textPrimary)
            .padding(Pixels(10))
            .frame(maxWidth: Pixels(.infinity), alignment: .leading)
            .background(isSelected ? Chrome.accentWash : Chrome.column)
            .cornerRadius(Pixels(7))
            .onClick(onSelect)
    }
}
