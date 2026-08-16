import Foundation

/// Keeps EditorState's device fields live while the DEV pane is open, and
/// stops the moment it closes -- nothing runs in the background while the
/// user is editing a keymap.
///
/// Deliberately cheap: presence comes from retrieveConnectedPeripherals (a
/// system query, no radio scan) and from delegate callbacks. Only RSSI is
/// genuinely polled. The one expensive operation, scanning for an idle
/// board, is duty-cycled and stops as soon as the board is found.
@MainActor
final class DeviceMonitor {
    static let shared = DeviceMonitor()

    private var task: Task<Void, Never>?

    func start(editor: EditorState) {
        guard task == nil else { return }
        task = Task { @MainActor in
            var tick = 0
            while !Task.isCancelled {
                editor.refreshDeviceStatus()
                #if canImport(CoreBluetooth)
                if editor.bleState.isReady {
                    BLECentral.shared.readRSSI()
                } else if tick % 5 == 0 {
                    // Duty-cycled discovery: one attempt per ~15s while
                    // nothing is found, rather than a continuous scan.
                    try? await BLECentral.shared.connect()
                }
                #endif
                tick += 1
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
