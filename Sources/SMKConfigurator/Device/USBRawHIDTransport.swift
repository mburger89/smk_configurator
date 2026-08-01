import CHidapi
import Foundation

/// Talks to the RP2040 build's raw HID upload interface (vendor usage page
/// 0xFF00, usage 0x01 — see ports/rp2040/platform/usb_descriptors.c in the
/// SMK firmware repo) via hidapi, a cross-platform USB/BLE HID library —
/// this keeps the USB path portable to Linux/Windows, unlike the
/// macOS-only IOKit HID Manager it replaces.
final class USBRawHIDTransport: DeviceTransport {
    private static let vendorID: UInt16 = 0x16C0
    private static let productID: UInt16 = 0x05DF
    private static let usagePage: UInt16 = 0xFF00
    private static let usage: UInt16 = 0x01

    // hidapi's `hid_device*` handle (OpaquePointer) isn't Sendable, but all
    // access to it is serialized through `queue` below, so it's safe to
    // share across the async closure boundary in `send(_:)`. This box just
    // asserts that to the compiler; it adds no behavior of its own.
    private struct DeviceBox: @unchecked Sendable {
        let device: OpaquePointer
    }

    private let device: OpaquePointer
    private let queue = DispatchQueue(label: "USBRawHIDTransport")

    init() throws {
        hid_init()

        // hid_open(vid, pid, nil) opens the first matching device, which
        // isn't precise enough here: this VID/PID also matches the
        // keyboard's own boot-HID interface. Enumerate and match on usage
        // page/usage (mirrors the IOKit matching dictionary this
        // replaces), then open the matched device by its path.
        guard let list = hid_enumerate(Self.vendorID, Self.productID) else {
            throw DeviceTransportError.noDeviceFound
        }
        defer { hid_free_enumeration(list) }

        var matchedPath: String?
        var current: UnsafeMutablePointer<hid_device_info>? = list
        while let info = current {
            if info.pointee.usage_page == Self.usagePage, info.pointee.usage == Self.usage,
               let path = info.pointee.path {
                matchedPath = String(cString: path)
                break
            }
            current = info.pointee.next
        }

        guard let path = matchedPath, let opened = hid_open_path(path) else {
            throw DeviceTransportError.noDeviceFound
        }
        device = opened
    }

    deinit {
        hid_close(device)
    }

    func send(_ packet: [UInt8]) async throws -> [UInt8] {
        let box = DeviceBox(device: device)
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [box] in
                let device = box.device
                // hid_write's calling convention always expects a leading
                // Report ID byte, 0x0 for devices (like this one) that
                // don't use numbered reports — see hidapi.h's hid_write
                // doc comment. The actual on-the-wire USB packet is still
                // exactly KeymapUploadProtocol.packetLength (32) bytes;
                // this leading 0x00 is purely hidapi's buffer convention.
                var writeBuffer = [UInt8](repeating: 0, count: packet.count + 1)
                writeBuffer[1...] = packet[...]
                let written = writeBuffer.withUnsafeBufferPointer { ptr in
                    hid_write(device, ptr.baseAddress, ptr.count)
                }
                guard written == writeBuffer.count else {
                    continuation.resume(throwing: DeviceTransportError.noDeviceFound)
                    return
                }

                // Symmetric leading-byte handling on read: some hidapi
                // backends echo a leading report-ID placeholder in the
                // read buffer, others don't (a known platform
                // inconsistency — verify against real hardware). Always
                // return exactly the last packet.count bytes actually
                // read, regardless of which case this turns out to be.
                var readBuffer = [UInt8](repeating: 0, count: packet.count + 1)
                let readCount = Int(readBuffer.withUnsafeMutableBufferPointer { ptr in
                    hid_read_timeout(device, ptr.baseAddress, ptr.count, 1000)
                })
                guard readCount > 0 else {
                    continuation.resume(throwing: DeviceTransportError.noDeviceFound)
                    return
                }
                let response = Array(readBuffer[max(0, readCount - packet.count)..<readCount])
                continuation.resume(returning: response)
            }
        }
    }
}
