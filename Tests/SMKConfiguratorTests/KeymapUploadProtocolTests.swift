import Testing
@testable import SMKConfigurator

@Suite("KeymapUploadProtocol frames BEGIN/CHUNK/COMMIT/ERASE packets correctly")
struct KeymapUploadProtocolTests {
    @Test("begin() encodes opcode 0x01 and total length as u16 LE")
    func beginEncoding() {
        let packet = KeymapUploadProtocol.begin(totalLen: 0x0102)
        #expect(packet.count == 32)
        #expect(packet[0] == 0x01)
        #expect(packet[1] == 0x02)
        #expect(packet[2] == 0x01)
    }

    @Test("chunk() encodes opcode 0x02, offset, length, and data")
    func chunkEncoding() {
        let data: [UInt8] = [0xAA, 0xBB, 0xCC]
        let packet = KeymapUploadProtocol.chunk(offset: 0x0010, data: data[...])
        #expect(packet[0] == 0x02)
        #expect(packet[1] == 0x10)
        #expect(packet[2] == 0x00)
        #expect(packet[3] == 3)
        #expect(Array(packet[4..<7]) == data)
    }

    @Test("commit() encodes opcode 0x03 and crc32 as u32 LE")
    func commitEncoding() {
        let packet = KeymapUploadProtocol.commit(crc32: 0x04030201)
        #expect(packet[0] == 0x03)
        #expect(Array(packet[1...4]) == [0x01, 0x02, 0x03, 0x04])
    }

    @Test("erase() encodes opcode 0x04 with no payload")
    func eraseEncoding() {
        let packet = KeymapUploadProtocol.erase()
        #expect(packet[0] == 0x04)
        #expect(packet[1...].allSatisfy { $0 == 0 })
    }

    @Test("crc32 matches the known IEEE 802.3 test vector for \"123456789\"")
    func crc32KnownVector() {
        let bytes = Array("123456789".utf8)
        #expect(KeymapUploadProtocol.crc32(bytes) == 0xCBF43926)
    }

    @Test("isAck reads the status byte")
    func ackDetection() {
        #expect(KeymapUploadProtocol.isAck([0x00, 0x01]))
        #expect(!KeymapUploadProtocol.isAck([0x01, 0x01]))
    }
}

@Suite("KeymapUploader drives BEGIN/CHUNK.../COMMIT over a transport")
struct KeymapUploaderTests {
    final class MockTransport: DeviceTransport {
        var sent: [[UInt8]] = []
        var responses: [[UInt8]]
        init(responses: [[UInt8]]) { self.responses = responses }
        func send(_ packet: [UInt8]) async throws -> [UInt8] {
            sent.append(packet)
            return responses.isEmpty ? [0x00, 0x00] : responses.removeFirst()
        }
    }

    @Test("uploads a small JSON payload as BEGIN, one CHUNK, then COMMIT")
    func fullUpload() async throws {
        let json = #"{"layers":[]}"#
        let transport = MockTransport(responses: [])
        try await KeymapUploader.upload(json: json, using: transport)

        #expect(transport.sent.count == 3)
        #expect(transport.sent[0][0] == 0x01) // BEGIN
        #expect(transport.sent[1][0] == 0x02) // CHUNK
        #expect(transport.sent[2][0] == 0x03) // COMMIT

        let expectedCrc = KeymapUploadProtocol.crc32(Array(json.utf8))
        let sentCrcBytes = Array(transport.sent[2][1...4])
        let sentCrc = UInt32(sentCrcBytes[0]) | (UInt32(sentCrcBytes[1]) << 8) |
                      (UInt32(sentCrcBytes[2]) << 16) | (UInt32(sentCrcBytes[3]) << 24)
        #expect(sentCrc == expectedCrc)
    }

    @Test("throws .nak when the device NAKs any packet")
    func nakPropagates() async {
        let transport = MockTransport(responses: [[0x01, 0x01]]) // NAK on BEGIN
        await #expect(throws: DeviceTransportError.nak) {
            try await KeymapUploader.upload(json: "{}", using: transport)
        }
    }

    @Test("throws .payloadTooLarge for JSON exceeding the store's capacity")
    func payloadTooLarge() async {
        let json = String(repeating: "x", count: 4086)
        let transport = MockTransport(responses: [])
        await #expect(throws: DeviceTransportError.payloadTooLarge) {
            try await KeymapUploader.upload(json: json, using: transport)
        }
    }
}
