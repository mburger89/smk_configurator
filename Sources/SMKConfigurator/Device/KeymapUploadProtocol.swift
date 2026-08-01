import Foundation

/// 32-byte packet framing for the BEGIN/CHUNK/COMMIT/ERASE keymap-upload
/// protocol shared with the firmware (Sources/componets/
/// smk_keymap_protocol.c in the SMK firmware repo). See
/// ~/esp/SMK/docs/superpowers/specs/2026-07-31-runtime-keymap-updates-design.md.
enum KeymapUploadProtocol {
    static let packetLength = 32
    static let maxChunkDataLength = 28 // packetLength - 4-byte CHUNK header

    private enum Opcode: UInt8 {
        case begin = 0x01
        case chunk = 0x02
        case commit = 0x03
        case erase = 0x04
    }

    static func begin(totalLen: UInt16) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: packetLength)
        p[0] = Opcode.begin.rawValue
        p[1] = UInt8(totalLen & 0xFF)
        p[2] = UInt8((totalLen >> 8) & 0xFF)
        return p
    }

    static func chunk(offset: UInt16, data: ArraySlice<UInt8>) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: packetLength)
        p[0] = Opcode.chunk.rawValue
        p[1] = UInt8(offset & 0xFF)
        p[2] = UInt8((offset >> 8) & 0xFF)
        p[3] = UInt8(data.count)
        for (i, byte) in data.enumerated() {
            p[4 + i] = byte
        }
        return p
    }

    static func commit(crc32: UInt32) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: packetLength)
        p[0] = Opcode.commit.rawValue
        p[1] = UInt8(crc32 & 0xFF)
        p[2] = UInt8((crc32 >> 8) & 0xFF)
        p[3] = UInt8((crc32 >> 16) & 0xFF)
        p[4] = UInt8((crc32 >> 24) & 0xFF)
        return p
    }

    static func erase() -> [UInt8] {
        var p = [UInt8](repeating: 0, count: packetLength)
        p[0] = Opcode.erase.rawValue
        return p
    }

    /// Standard bitwise IEEE 802.3 / zlib-compatible CRC32 (poly 0xEDB88320,
    /// init/final 0xFFFFFFFF) — implemented independently (no shared
    /// library) on both firmware platforms and here, matching by
    /// construction rather than by dependency.
    static func crc32(_ data: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                let mask = UInt32(bitPattern: -Int32(bitPattern: crc & 1))
                crc = (crc >> 1) ^ (0xEDB88320 & mask)
            }
        }
        return crc ^ 0xFFFFFFFF
    }

    static func isAck(_ response: [UInt8]) -> Bool {
        response.first == 0x00
    }
}
