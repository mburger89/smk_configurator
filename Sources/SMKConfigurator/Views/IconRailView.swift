import SwiftCrossUI

/// The leftmost 64px pane: 5 square buttons that switch the whole workspace
/// between KEY/DSN/THM/DEV/MAC. The only navigation in this screen -- no back
/// button, since state is mode-based rather than stack-based.
struct IconRailView: View {
    @Binding var mode: RailMode

    @Environment(\.colorScheme) private var colorScheme
    private var chrome: Chrome { Chrome(scheme: colorScheme) }

    var body: some View {
        VStack(spacing: 16) {
            RailButton(icon: .key, tooltip: "Keymap", isActive: mode == .key) { mode = .key }
            RailButton(icon: .designs, tooltip: "Designs", isActive: mode == .designs) { mode = .designs }
            RailButton(icon: .themes, tooltip: "Themes", isActive: mode == .themes) { mode = .themes }
            RailButton(icon: .device, tooltip: "Device", isActive: mode == .device) { mode = .device }
            RailButton(icon: .macros, tooltip: "Macros", isActive: mode == .macros) {
                mode = .macros
            }
            Spacer()
        }
        .padding(EdgeInsets(top: 16, bottom: 16, leading: 0, trailing: 0))
        .frame(width: 64)
        .frame(maxHeight: .infinity)
        .background(chrome.bar)
    }
}
