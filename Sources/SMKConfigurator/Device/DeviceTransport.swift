import Foundation

/// A channel that can carry one keymap-upload packet round trip. Two
/// concrete implementations: USBRawHIDTransport (IOKit HID, RP2040) and
/// BLETransport (CoreBluetooth, ESP32-C6) — see those files.
protocol DeviceTransport {
    func send(_ packet: [UInt8]) async throws -> [UInt8]
}

enum DeviceTransportError: Error, Equatable {
    case noDeviceFound
    case nak
    case payloadTooLarge
    case encodingFailed
}

/// Drives a full keymap upload (BEGIN, N x CHUNK, COMMIT) over any
/// DeviceTransport. Transport-agnostic — the same sequence works whether
/// bytes travel over USB raw HID or a BLE GATT characteristic.
enum KeymapUploader {
    /// Must match the firmware's SMK_KEYMAP_MAX_LEN (Sources/componets/
    /// smk_keymap_store.c / ports/rp2040/platform/smk_keymap_store.c).
    static let maxPayloadLength = 4085

    static func upload(json: String, using transport: DeviceTransport) async throws {
        let bytes = Array(json.utf8)
        guard bytes.count <= maxPayloadLength else {
            throw DeviceTransportError.payloadTooLarge
        }

        let beginResponse = try await transport.send(
            KeymapUploadProtocol.begin(totalLen: UInt16(bytes.count))
        )
        guard KeymapUploadProtocol.isAck(beginResponse) else {
            throw DeviceTransportError.nak
        }

        var offset = 0
        while offset < bytes.count {
            let end = min(offset + KeymapUploadProtocol.maxChunkDataLength, bytes.count)
            let response = try await transport.send(
                KeymapUploadProtocol.chunk(offset: UInt16(offset), data: bytes[offset..<end])
            )
            guard KeymapUploadProtocol.isAck(response) else {
                throw DeviceTransportError.nak
            }
            offset = end
        }

        let crc = KeymapUploadProtocol.crc32(bytes)
        let commitResponse = try await transport.send(KeymapUploadProtocol.commit(crc32: crc))
        guard KeymapUploadProtocol.isAck(commitResponse) else {
            throw DeviceTransportError.nak
        }
    }
}
