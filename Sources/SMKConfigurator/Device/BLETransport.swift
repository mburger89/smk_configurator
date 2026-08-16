#if canImport(CoreBluetooth)
import Foundation

/// Carries keymap-upload packets over the firmware's custom GATT service
/// (see ble_helper.c's smk_upload_svcs). The HID Report ID 2 channel this
/// replaces was unreachable on macOS: Core Bluetooth hides the HID service
/// from apps entirely. Discovery, connection and characteristic lookup live
/// in BLECentral, which the DEV pane's monitor shares -- duplicating them
/// here is how the two would drift.
@MainActor
final class BLETransport: DeviceTransport {
    private let session: BLECentral

    init(session: BLECentral = .shared) {
        self.session = session
    }

    func connect() async throws {
        try await session.connect()
    }

    func send(_ packet: [UInt8]) async throws -> [UInt8] {
        try await session.send(packet)
    }
}
#endif
