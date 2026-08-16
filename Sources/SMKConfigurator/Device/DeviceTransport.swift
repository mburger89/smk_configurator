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
    case transportFailure(String)
}

/// Drives a full keymap upload (BEGIN, N x CHUNK, COMMIT) over any
/// DeviceTransport. Transport-agnostic — the same sequence works whether
/// bytes travel over USB raw HID or a BLE GATT characteristic.
enum KeymapUploader {
    /// Must match the firmware's `smkKeymapMaxLen` (Sources/SMKCore/
    /// KeymapFrame.swift, shared by the ESP32-C6 NVS store and the RP2040
    /// flash store).
    static let maxPayloadLength = 4085

    /// Where an upload has got to, for the DEV pane's progress read-out. A
    /// ~4 KB keymap is ~146 round trips, so this is several visible seconds.
    enum UploadPhase: Equatable {
        case begin
        case chunk(index: Int, of: Int)
        case commit
    }

    static func upload(
        json: String,
        using transport: DeviceTransport,
        progress: (@MainActor (UploadPhase) -> Void)? = nil
    ) async throws {
        let bytes = Array(json.utf8)
        guard bytes.count <= maxPayloadLength else {
            throw DeviceTransportError.payloadTooLarge
        }

        await progress?(.begin)
        let beginResponse = try await transport.send(
            KeymapUploadProtocol.begin(totalLen: UInt16(bytes.count))
        )
        guard KeymapUploadProtocol.isAck(beginResponse) else {
            throw DeviceTransportError.nak
        }

        let chunkCount = (bytes.count + KeymapUploadProtocol.maxChunkDataLength - 1)
            / KeymapUploadProtocol.maxChunkDataLength
        var chunkIndex = 0
        var offset = 0
        while offset < bytes.count {
            let end = min(offset + KeymapUploadProtocol.maxChunkDataLength, bytes.count)
            await progress?(.chunk(index: chunkIndex, of: chunkCount))
            let response = try await transport.send(
                KeymapUploadProtocol.chunk(offset: UInt16(offset), data: bytes[offset..<end])
            )
            guard KeymapUploadProtocol.isAck(response) else {
                throw DeviceTransportError.nak
            }
            chunkIndex += 1
            offset = end
        }

        await progress?(.commit)
        let crc = KeymapUploadProtocol.crc32(bytes)
        let commitResponse = try await transport.send(KeymapUploadProtocol.commit(crc32: crc))
        guard KeymapUploadProtocol.isAck(commitResponse) else {
            throw DeviceTransportError.nak
        }
    }
}
