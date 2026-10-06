import Foundation
import MetalUI

// DEV mode (port plan §1.8): transport cards, the connection status with Send
// to Device, and the device info inspector.

/// DEV rail mode's list column: one card per transport. USB's card reflects
/// `EditorState.refreshDeviceStatus`'s presence probe; BLE's (macOS only)
/// reflects `DeviceMonitor`'s live session state, kept current while the DEV
/// pane is on screen.
struct DeviceListColumnView: Component {
    let editor: EditorState

    var content: some ElementGroup {
        pane {
            ListColumn {
                ListSection(spacing: 8) {
                    SectionHeader(title: "Transports")
                    TransportCard(name: "USB (RP2040)",
                                  dotColor: editor.usbConnected ? Chrome.connectedDot : Chrome.disconnectedDot,
                                  headline: editor.usbConnected ? "Connected" : "Not connected",
                                  detail: nil)
                    #if canImport(CoreBluetooth)
                    TransportCard(name: "BLE (ESP32-C6)", dotColor: bleDotColor, headline: bleHeadline,
                                  detail: editor.bleState.summary)
                    #endif
                }
            }
        }
    }

    #if canImport(CoreBluetooth)
    /// `.connected` (linked, but the upload service is missing -- the
    /// signature of a firmware/app UUID mismatch) and `.failed` (radio off,
    /// access denied) read as something to act on, not as the same grey dot
    /// as an absent keyboard.
    private var bleDotColor: Color {
        switch editor.bleState {
        case .ready: Chrome.connectedDot
        case .connected, .failed: Chrome.dangerText
        default: Chrome.disconnectedDot
        }
    }

    /// Kept consistent with `BLEConnectionState.summary`, the card's detail
    /// line under this headline -- neither may contradict the other.
    private var bleHeadline: String {
        switch editor.bleState {
        case .ready: "Connected"
        case .connected: "Linked — service missing"
        case .failed: "Unavailable"
        default: "Not connected"
        }
    }
    #endif
}

/// One transport card: a dot and the transport's name, a headline, and an
/// optional detail line, on `surface` with a hairline border, radius 8.
struct TransportCard: Component {
    var name: String
    var dotColor: Color
    var headline: String
    var detail: String?

    var content: some ElementGroup {
        Column(gap: Pixels(4)) {
            Row(gap: Pixels(6)) {
                StatusDot(color: dotColor, diameter: 8)
                Text(name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Chrome.textPrimary)
            }
            Text(headline)
                .font(.system(size: 11))
                .foregroundColor(Chrome.textTertiary)
            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(Chrome.textTertiary)
            }
        }
        .alignItems(.flexStart)
        .padding(Pixels(10))
        .frame(maxWidth: Pixels(.infinity), alignment: .leading)
        .background(Chrome.surface)
        .cornerRadius(Pixels(8))
        .border(Chrome.dividerLight, width: Pixels(1))
    }
}

/// Which transport the DEV pane speaks for. `EditorState.sendToDevice()`
/// tries USB first and falls back to BLE, so the headline and the
/// inspector's MCU row answer for both rather than each hard-coding USB.
enum DeviceTransportStatus: Equatable {
    case usb
    case bleReady
    /// Linked, but the upload service is missing -- a firmware/app UUID
    /// mismatch, kept distinct from "not connected" as the card does.
    case bleServiceMissing
    case bleBusy(String)
    case bleFailed(String)
    case disconnected

    @MainActor
    static func current(_ editor: EditorState) -> DeviceTransportStatus {
        if editor.usbConnected { return .usb }
        #if canImport(CoreBluetooth)
        switch editor.bleState {
        case .ready: return .bleReady
        case .connected: return .bleServiceMissing
        case .searching, .connecting: return .bleBusy(editor.bleState.summary)
        case .failed: return .bleFailed(editor.bleState.summary)
        case .idle: return .disconnected
        }
        #else
        return .disconnected
        #endif
    }

    var headline: String {
        switch self {
        case .usb: "Connected via USB"
        case .bleReady: "Connected via BLE"
        case .bleServiceMissing: "Linked — upload service missing"
        case .bleBusy(let summary): summary
        case .bleFailed(let summary): summary
        case .disconnected: "Not connected"
        }
    }

    var mcu: String {
        switch self {
        case .usb: "RP2040"
        case .bleReady, .bleServiceMissing: "ESP32-C6"
        case .bleBusy, .bleFailed, .disconnected: "—"
        }
    }

    var dotColor: Color {
        switch self {
        case .usb, .bleReady: Chrome.connectedDot
        case .bleServiceMissing, .bleFailed: Chrome.dangerText
        case .bleBusy, .disconnected: Chrome.disconnectedDot
        }
    }
}

/// The DEV pane's text for an upload phase and for "Last sent …", as plain
/// functions so they are testable (`DeviceStatusTextTests`).
enum DeviceStatusText {
    static func progress(_ phase: KeymapUploader.UploadPhase) -> String {
        switch phase {
        case .begin: "Starting upload…"
        case .chunk(let index, let total): "Sending chunk \(index + 1) of \(total)…"
        case .commit: "Committing…"
        }
    }

    static func relativeTime(from date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        return "\(minutes / 60)h ago"
    }
}

/// DEV rail mode's main content: connection status, the board summary, Send
/// to Device (and, on macOS, Test Connection), upload progress and when the
/// keymap was last sent.
///
/// The device monitor runs while this pane is on screen: started in
/// `onAppear`, stopped in `onDisappear` (MetalUI runs both after the build,
/// outside every phase, so the monitor's writes to the model are input-time
/// writes).
struct DeviceMainContentView: Component {
    let editor: EditorState

    var content: some ElementGroup {
        pane {
            let editor = editor
            let status = DeviceTransportStatus.current(editor)
            Column(gap: Pixels(10)) {
                StatusDot(color: status.dotColor, diameter: 14)
                Text(status.headline)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Chrome.textPrimary)
                Text("\(editor.activeDesign.name) · \(status.mcu) · fw \(firmwareVersionLabel)")
                    .font(.system(size: 13))
                    .foregroundColor(Chrome.textSecondary)
                InspectorButton(label: editor.isSendingToDevice ? "Sending…" : "Send to Device",
                                isPrimary: true, isEnabled: !editor.isSendingToDevice) {
                    editor.sendToDevice()
                }
                .frame(width: Pixels(180))
                #if canImport(CoreBluetooth)
                InspectorButton(label: "Test Connection", isEnabled: !editor.isSendingToDevice) {
                    editor.testBLEConnection()
                }
                .frame(width: Pixels(180))
                #endif
                if let phase = editor.uploadProgress {
                    Text(DeviceStatusText.progress(phase))
                        .font(.system(size: 12))
                        .foregroundColor(Chrome.textSecondary)
                }
                if let lastSentAt = editor.lastSentAt {
                    Text("Last sent \(DeviceStatusText.relativeTime(from: lastSentAt))")
                        .font(.system(size: 12))
                        .foregroundColor(Chrome.textTertiary)
                }
            }
            .padding(Pixels(20))
            .frame(maxWidth: Pixels(.infinity), maxHeight: Pixels(.infinity))
            .background(Chrome.canvas)
            .onAppear {
                editor.refreshDeviceStatus()
                DeviceMonitor.shared.start(editor: editor)
            }
            .onDisappear {
                DeviceMonitor.shared.stop()
            }
        }
    }
}

/// DEV rail mode's inspector: a definition list of the active design and the
/// connection.
struct DeviceInspectorView: Component {
    let editor: EditorState

    var content: some ElementGroup {
        pane {
            InspectorColumn {
                InspectorHeading(title: "Device info")
                Divider()
                Column(gap: Pixels(6)) {
                    DetailLine(label: "Board", value: editor.activeDesign.name, size: 12)
                    DetailLine(label: "MCU", value: DeviceTransportStatus.current(editor).mcu, size: 12)
                    DetailLine(label: "Matrix", value: "\(editor.activeDesign.rowCount)×\(editor.activeDesign.colCount)",
                               size: 12)
                    DetailLine(label: "Firmware", value: firmwareVersionLabel, size: 12)
                    DetailLine(label: "Layers on device", value: "\(editor.document.layers.count)", size: 12)
                    #if canImport(CoreBluetooth)
                    DetailLine(label: "BLE", value: editor.bleState.summary, size: 12)
                    DetailLine(label: "Peripheral", value: editor.blePeripheralName ?? "—", size: 12)
                    DetailLine(label: "Signal", value: editor.bleRSSI.map { "\($0) dBm" } ?? "—", size: 12)
                    DetailLine(label: "Max write", value: editor.bleMTU.map { "\($0) B" } ?? "—", size: 12)
                    #endif
                }
                .alignItems(.stretch)
            }
        }
    }
}
