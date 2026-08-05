import SwiftCrossUI

/// The leftmost 64px pane: 4 square buttons that switch the whole workspace
/// between KEY/DSN/THM/DEV. The only navigation in this screen -- no back
/// button, since state is mode-based rather than stack-based.
struct IconRailView: View {
    @Binding var mode: RailMode

    var body: some View {
        VStack(spacing: 16) {
            RailButton(label: "KEY", isActive: mode == .key) { mode = .key }
            RailButton(label: "DSN", isActive: mode == .designs) { mode = .designs }
            RailButton(label: "THM", isActive: mode == .themes) { mode = .themes }
            RailButton(label: "DEV", isActive: mode == .device) { mode = .device }
            Spacer()
        }
        .padding(EdgeInsets(top: 16, bottom: 16, leading: 0, trailing: 0))
        .frame(width: 64)
        .frame(maxHeight: .infinity)
        .background(Chrome.bar)
    }
}
