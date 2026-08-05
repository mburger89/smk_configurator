import Foundation
import SwiftCrossUI

/// DEV rail mode's List column: one card per transport. BLE has no live
/// connection tracking yet (see `EditorState.refreshDeviceStatus`, which
/// only probes USB), so it's always shown as not connected.
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
                    transportCard(name: "BLE (ESP32-C6)", isConnected: false)
                }
            }
            .padding(EdgeInsets(top: 12, bottom: 12, leading: 10, trailing: 10))
        }
        .frame(width: 260)
        .frame(maxHeight: .infinity)
        .background(chrome.column)
    }

    private func transportCard(name: String, isConnected: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(chrome.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(chrome.dividerLight, style: StrokeStyle(width: 1))
                }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    StatusDot(color: isConnected ? chrome.connectedDot : chrome.disconnectedDot, diameter: 8)
                    Text(name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(chrome.textPrimary)
                }
                Text(isConnected ? "Connected" : "Not connected")
                    .font(.system(size: 11))
                    .foregroundColor(chrome.textTertiary)
            }
            .padding(10)
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
            StatusDot(color: editor.usbConnected ? chrome.connectedDot : chrome.disconnectedDot, diameter: 14)
            Text(editor.usbConnected ? "Connected via USB" : "Not connected")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(chrome.textPrimary)
            Text("\(editor.activeDesign.name) · RP2040 · fw \(firmwareVersionLabel)")
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
                infoLine("MCU", editor.usbConnected ? "RP2040" : "—")
                infoLine("Matrix", "\(editor.activeDesign.rowCount)×\(editor.activeDesign.colCount)")
                infoLine("Firmware", firmwareVersionLabel)
                infoLine("Layers on device", "\(editor.document.layers.count)")
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
