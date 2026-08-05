import SwiftCrossUI

/// One cell in the DSN grid editor: shows its width (or "×" for a gap), tap
/// to select it for editing in the footer strip below.
struct DesignCellView: View {
    var cell: KeyboardDesign.Cell
    var isSelected: Bool
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var chrome: Chrome { Chrome(scheme: colorScheme) }

    static let unit: Double = 52
    static let height: Double = 44
    static let spacing: Double = 4

    var body: some View {
        let width = cell.isGap ? Self.unit : cell.width * Self.unit + (cell.width - 1) * Self.spacing

        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(cell.isGap ? Color.black : chrome.surface)
            Text(cell.isGap ? "×" : formatWidth(cell.width))
                .font(.system(size: 12))
                .foregroundColor(cell.isGap ? chrome.textTertiary : chrome.textPrimary)
        }
        .frame(width: width, height: Self.height)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(chrome.accent, style: StrokeStyle(width: 2))
            }
        }
        .onTapGesture {
            action()
        }
    }

    private func formatWidth(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", w)
            : String(format: "%.2f", w)
    }
}
