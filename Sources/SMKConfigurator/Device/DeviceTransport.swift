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

/// The board's real macro/keymap capacity, decoded from a `CAPS` opcode
/// (0x05) response -- see `KeymapUploader.queryCapacity(using:)` below and
/// `EditorState.applyDeviceCapacity(_:deviceKey:)`, which turns this into
/// the meter's `MacroCapacity`/`MacroCapacitySource`.
///
/// Two things here look like bugs and are not -- both are deliberate on the
/// firmware side (see `~/esp/SMK/Sources/SMKCore/KeymapProtocol.swift`'s
/// `smkKeymapRealCaps()` doc comment):
/// - `macroBytes == keymapMaxLen` on a real board. Macros have no separate
///   storage region -- they share one payload budget with layers -- so the
///   board reports the shared ceiling and the editor works out real macro
///   headroom by subtracting what the compiled layers cost (a different
///   task; this type only stores what the board says).
/// - `macroSlots` maxes out at 255, not 256. A macro id is one byte (256
///   possible values), but the wire field carrying `macroSlots` is also one
///   byte, so 256 itself can't be represented. Understating by one is the
///   safe direction.
struct DeviceCapacityReport: Equatable {
    var macroBytes: Int
    var macroSlots: Int
    var keymapMaxLen: Int
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
        payload bytes: [UInt8],
        using transport: DeviceTransport,
        progress: (@MainActor (UploadPhase) -> Void)? = nil
    ) async throws {
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

    /// The `CAPS` opcode (0x05, see `~/esp/SMK/Sources/SMKCore/
    /// KeymapProtocol.swift`'s `smkKeymapOpCaps`) -- not part of
    /// `KeymapUploadProtocol` because that enum's other four opcodes
    /// (BEGIN/CHUNK/COMMIT/ERASE) belong to a different task's file scope;
    /// this is the one CAPS needs, framed the same way (a
    /// `KeymapUploadProtocol.packetLength`-byte packet, opcode in byte 0,
    /// zero-filled otherwise).
    ///
    /// Response layout, matching the little-endian convention BEGIN's own
    /// total-length field already uses: byte 0 status (0x00 ok, else
    /// error), byte 1 opcode echo, bytes 2-3 `macroBytes` (u16 LE), byte 4
    /// `macroSlots` (u8), bytes 5-6 `keymapMaxLen` (u16 LE).
    static func queryCapacity(using transport: DeviceTransport) async throws -> DeviceCapacityReport {
        var packet = [UInt8](repeating: 0, count: KeymapUploadProtocol.packetLength)
        packet[0] = 0x05
        let response = try await transport.send(packet)
        guard KeymapUploadProtocol.isAck(response), response.count >= 7 else {
            throw DeviceTransportError.nak
        }
        let macroBytes = Int(response[2]) | (Int(response[3]) << 8)
        let macroSlots = Int(response[4])
        let keymapMaxLen = Int(response[5]) | (Int(response[6]) << 8)
        return DeviceCapacityReport(macroBytes: macroBytes, macroSlots: macroSlots, keymapMaxLen: keymapMaxLen)
    }
}
