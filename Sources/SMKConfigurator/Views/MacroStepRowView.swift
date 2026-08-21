import SwiftCrossUI

/// One row in the macro sequence view: reorder controls, an index, a type
/// badge, a per-type payload summary, right-aligned metadata, and delete.
///
/// The reorder (▲▼) and delete (✕) controls must not be nested inside the
/// row-selection `TapTarget`'s own content closure. SwiftCrossUI's
/// `onTapGesture` has to be the outermost gesture on its subtree to reliably
/// receive clicks (see the doc comment on `hoveredLayerIndex` in
/// `KeyModeViews.swift` for the same constraint hit earlier with the layer
/// list's delete glyph) -- a second, independent tap target can't be nested
/// inside a first at all, they have to be siblings under a shared,
/// gesture-free parent. So `controlColumn` and `deleteButton` sit as true
/// siblings of the selectable `TapTarget` in this view's outer `HStack`,
/// rather than inside its `content` closure.
struct MacroStepRowView: View {
    var step: MacroStep
    var index: Int
    var isSelected: Bool
    var onSelect: () -> Void
    var onMoveUp: () -> Void
    var onMoveDown: () -> Void
    var onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var chrome: Chrome { Chrome(scheme: colorScheme) }

    var body: some View {
        HStack(spacing: 12) {
            controlColumn
            TapTarget(
                background: isSelected ? chrome.accentWash : chrome.column,
                cornerRadius: 7,
                border: isSelected ? chrome.accent : Color.white.opacity(0.05),
                action: onSelect
            ) {
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(chrome.textTertiary)
                        .frame(width: 14, alignment: .leading)
                    typeBadge
                    Text(step.payloadSummary)
                        .font(.system(size: 12))
                        .foregroundColor(chrome.textPrimary)
                    Spacer()
                    Text(step.metadataLabel)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(chrome.textTertiary)
                }
                .padding(EdgeInsets(top: 10, bottom: 10, leading: 13, trailing: 13))
            }
            deleteButton
        }
    }

    /// ▲▼ reorder buttons, stacked in an 11pt-wide column. Each carries its
    /// own independent `onTapGesture` -- see the type doc comment.
    private var controlColumn: some View {
        VStack(spacing: 2) {
            Text("▲")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(chrome.textSecondary)
                .onTapGesture(perform: onMoveUp)
            Text("▼")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(chrome.textSecondary)
                .onTapGesture(perform: onMoveDown)
        }
        .frame(width: 11)
    }

    /// The three-letter step-type badge (`step.typeCode`).
    private var typeBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(chrome.chipBackground)
            Text(step.typeCode)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(chrome.textSecondary)
        }
        .frame(width: 30, height: 18)
    }

    /// The trailing ✕ delete control -- a true sibling of the selection
    /// `TapTarget`, not nested inside it. See the type doc comment.
    private var deleteButton: some View {
        Text("✕")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(chrome.textTertiary)
            .onTapGesture(perform: onDelete)
    }
}
