import SwiftCrossUI

/// One cell in the `DesignBuilderView` grid editor: shows its width (or "x"
/// for a gap), tap to select it for editing in the inspector below.
struct DesignCellView: View {
    var cell: KeyboardDesign.Cell
    var isSelected: Bool
    var action: () -> Void

    static let unit: Double = 40
    static let spacing: Double = 4

    var body: some View {
        let width = cell.isGap ? Self.unit : cell.width * Self.unit + (cell.width - 1) * Self.spacing

        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(cell.isGap ? Color.black : Color.white)
            Text(cell.isGap ? "×" : formatWidth(cell.width))
                .font(.system(size: 11))
                .foregroundColor(cell.isGap ? .gray : .black)
        }
        .frame(width: width, height: Self.unit)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.blue, style: StrokeStyle(width: 2))
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
