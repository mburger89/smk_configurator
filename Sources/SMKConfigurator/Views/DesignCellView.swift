import Foundation
import MetalUI

/// One cell in the DSN grid editor: its width ("1", "1.25", …) or "×" for a
/// gap; a click selects it for the footer's width presets. The selected cell
/// wears a 2-point accent ring.
struct DesignCellView: Component {
    var cell: KeyboardDesign.Cell
    var isSelected: Bool
    var action: @MainActor () -> Void

    static let unit: Float = 52
    static let height: Float = 44
    static let spacing: Float = 4

    /// A key `w` units wide spans `w` unit columns and the gaps between them;
    /// a gap cell is one unit wide.
    static func width(of cell: KeyboardDesign.Cell) -> Float {
        cell.isGap ? unit : Float(cell.width) * unit + (Float(cell.width) - 1) * spacing
    }

    /// "1", "2" for whole widths; "1.25", "2.75" otherwise.
    static func label(forWidth width: Double) -> String {
        width.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(width))
            : String(format: "%.2f", width)
    }

    var content: some ElementGroup {
        Button(action: action) {
            Text(cell.isGap ? "×" : Self.label(forWidth: cell.width))
                .font(.system(size: 12))
                .foregroundColor(cell.isGap ? Chrome.textTertiary : Chrome.textPrimary)
                .frame(width: Pixels(Self.width(of: cell)), height: Pixels(Self.height))
        }
        .buttonStyle(.plain)
        // The gap cell is the "physical board" black, whatever the scheme
        // (port plan §3.2).
        .background(cell.isGap ? Color.black : Chrome.surface)
        .cornerRadius(Pixels(6))
        .border(isSelected ? Chrome.accent : Color.clear, width: Pixels(2))
    }
}
