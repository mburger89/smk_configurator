import Foundation
import SwiftCrossUI

/// DEV rail mode's List column: one card per transport. USB's card reflects
/// `EditorState.refreshDeviceStatus`'s presence probe; BLE's reflects
/// `DeviceMonitor`'s live session state, kept current while this pane is on
/// screen.
struct DeviceListColumnView: View {
    @Environment(EditorState.self) var editor
    @Environment(\.colorScheme) private var colorScheme
    private var chrome: Chrome { Chrome(scheme: colorScheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Transports")
                    transportCard(name: "USB (RP2040)", isConnected: editor.usbConnected)
                    #if canImport(CoreBluetooth)
                    transportCard(
                        name: "BLE (ESP32-C6)",
                        isConnected: editor.bleState.isReady,
                        dotColor: bleDotColor,
                        headline: bleHeadline,
                        detail: editor.bleState.summary
                    )
                    #endif
                }
            }
            .padding(EdgeInsets(top: 12, bottom: 12, leading: 10, trailing: 10))
        }
        .frame(width: 260)
        .frame(maxHeight: .infinity)
        .background(chrome.column)
    }

    #if canImport(CoreBluetooth)
    /// `.connected` (linked, but the upload service is missing -- the
    /// signature of a firmware/app UUID mismatch) must read as visibly
    /// different from an absent keyboard, not blend into the same grey dot
    /// as `.idle`/`.searching`. `dangerText` is the closest existing
    /// attention-drawing token `Chrome` exposes.
    private var bleDotColor: Color {
        switch editor.bleState {
        case .ready: return chrome.connectedDot
        // `.failed` gets the same attention colour: "Bluetooth is off" or
        // "access was denied" is a thing the user can act on, not the same
        // nothing-here as `.idle`.
        case .connected, .failed: return chrome.dangerText
        default: return chrome.disconnectedDot
        }
    }

    /// Kept consistent with `BLEConnectionState.summary`, which becomes the
    /// card's detail line below this headline -- neither may contradict the
    /// other for the same state.
    private var bleHeadline: String {
        switch editor.bleState {
        case .ready: return "Connected"
        case .connected: return "Linked — service missing"
        // The `summary` line underneath carries the actual reason (radio
        // off, access denied, service missing); this only has to stop it
        // reading as an ordinary empty search.
        case .failed: return "Unavailable"
        default: return "Not connected"
        }
    }
    #endif

    private func transportCard(
        name: String,
        isConnected: Bool,
        dotColor: Color? = nil,
        headline: String? = nil,
        detail: String? = nil
    ) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(chrome.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(chrome.dividerLight, style: StrokeStyle(width: 1))
                }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    StatusDot(
                        color: dotColor ?? (isConnected ? chrome.connectedDot : chrome.disconnectedDot),
                        diameter: 8
                    )
                    Text(name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(chrome.textPrimary)
                }
                Text(headline ?? (isConnected ? "Connected" : "Not connected"))
                    .font(.system(size: 11))
                    .foregroundColor(chrome.textTertiary)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundColor(chrome.textTertiary)
                }
            }
            .padding(10)
        }
    }
}

/// Which transport the DEV pane should speak for. `EditorState.sendToDevice()`
/// tries USB first and falls back to BLE, so the pane's headline and the
/// inspector's MCU row have to answer for both rather than each hard-coding
/// USB -- the headline previously read "Not connected · RP2040" while a BLE
/// upload was succeeding over the very link the card beside it called Ready.
private enum DeviceTransportStatus {
    case usb
    case bleReady
    /// Linked, but the upload service is missing -- a firmware/app UUID
    /// mismatch, kept distinct from "not connected" for the same reason the
    /// transport card distinguishes them.
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

    func dotColor(_ chrome: Chrome) -> Color {
        switch self {
        case .usb, .bleReady: chrome.connectedDot
        case .bleServiceMissing, .bleFailed: chrome.dangerText
        case .bleBusy, .disconnected: chrome.disconnectedDot
        }
    }
}

/// DEV rail mode's Main content: connection status, board summary, and the
/// Send to Device action.
struct DeviceMainContentView: View {
    @Environment(EditorState.self) var editor
    @Environment(\.colorScheme) private var colorScheme
    private var chrome: Chrome { Chrome(scheme: colorScheme) }

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            let status = DeviceTransportStatus.current(editor)
            StatusDot(color: status.dotColor(chrome), diameter: 14)
            Text(status.headline)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(chrome.textPrimary)
            Text("\(editor.activeDesign.name) · \(status.mcu) · fw \(firmwareVersionLabel)")
                .font(.system(size: 13))
                .foregroundColor(chrome.textSecondary)
            InspectorButton(
                label: editor.isSendingToDevice ? "Sending…" : "Send to Device",
                isPrimary: true,
                isEnabled: !editor.isSendingToDevice
            ) {
                editor.sendToDevice()
            }
            .frame(width: 180)
            #if canImport(CoreBluetooth)
            InspectorButton(label: "Test Connection", isEnabled: !editor.isSendingToDevice) {
                editor.testBLEConnection()
            }
            .frame(width: 180)
            #endif
            if let phase = editor.uploadProgress {
                Text(progressLabel(phase))
                    .font(.system(size: 12))
                    .foregroundColor(chrome.textSecondary)
            }
            if let lastSentAt = editor.lastSentAt {
                Text("Last sent \(relativeTimeString(from: lastSentAt))")
                    .font(.system(size: 12))
                    .foregroundColor(chrome.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(chrome.canvas)
        .onAppear {
            editor.refreshDeviceStatus()
            DeviceMonitor.shared.start(editor: editor)
        }
        .onDisappear {
            DeviceMonitor.shared.stop()
        }
    }

    private func progressLabel(_ phase: KeymapUploader.UploadPhase) -> String {
        switch phase {
        case .begin: return "Starting upload…"
        case .chunk(let index, let total): return "Sending chunk \(index + 1) of \(total)…"
        case .commit: return "Committing…"
        }
    }

    private func relativeTimeString(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        return "\(hours)h ago"
    }
}

/// DEV rail mode's Inspector: a definition-list style read-out of the
/// currently active design/connection.
struct DeviceInspectorView: View {
    @Environment(EditorState.self) var editor
    @Environment(\.colorScheme) private var colorScheme
    private var chrome: Chrome { Chrome(scheme: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Device info")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(chrome.textPrimary)
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                infoLine("Board", editor.activeDesign.name)
                infoLine("MCU", DeviceTransportStatus.current(editor).mcu)
                infoLine("Matrix", "\(editor.activeDesign.rowCount)×\(editor.activeDesign.colCount)")
                infoLine("Firmware", firmwareVersionLabel)
                infoLine("Layers on device", "\(editor.document.layers.count)")
                #if canImport(CoreBluetooth)
                infoLine("BLE", editor.bleState.summary)
                infoLine("Peripheral", editor.blePeripheralName ?? "—")
                infoLine("Signal", editor.bleRSSI.map { "\($0) dBm" } ?? "—")
                infoLine("Max write", editor.bleMTU.map { "\($0) B" } ?? "—")
                #endif
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 300)
        .frame(maxHeight: .infinity)
        .background(chrome.column)
    }

    private func infoLine(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(chrome.textTertiary)
            Spacer()
            Text(value)
                .font(.system(size: 12))
                .foregroundColor(chrome.textSecondary)
        }
    }
}
