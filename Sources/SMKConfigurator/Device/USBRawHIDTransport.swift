import Foundation
import IOKit
import IOKit.hid

/// Talks to the RP2040 build's raw HID upload interface (vendor usage page
/// 0xFF00, usage 0x01 — see ports/rp2040/platform/usb_descriptors.c in the
/// SMK firmware repo) via IOKit's HID Manager.
final class USBRawHIDTransport: DeviceTransport {
    private static let vendorID = 0x16C0
    private static let productID = 0x05DF
    private static let usagePage = 0xFF00
    private static let usage = 0x01

    private let manager: IOHIDManager
    private let device: IOHIDDevice
    private let reportBuffer: UnsafeMutablePointer<UInt8>
    private let reportBufferLength = KeymapUploadProtocol.packetLength
    private var pendingContinuation: CheckedContinuation<[UInt8], Error>?
    private let queue = DispatchQueue(label: "USBRawHIDTransport")

    init() throws {
        reportBuffer = .allocate(capacity: reportBufferLength)
        reportBuffer.initialize(repeating: 0, count: reportBufferLength)

        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: Self.vendorID,
            kIOHIDProductIDKey: Self.productID,
            kIOHIDPrimaryUsagePageKey: Self.usagePage,
            kIOHIDPrimaryUsageKey: Self.usage,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess,
              let matched = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>)?.first
        else {
            reportBuffer.deallocate()
            throw DeviceTransportError.noDeviceFound
        }
        device = matched

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            device, reportBuffer, reportBufferLength,
            { context, _, _, _, _, report, length in
                guard let context else { return }
                let transport = Unmanaged<USBRawHIDTransport>.fromOpaque(context).takeUnretainedValue()
                let bytes = Array(UnsafeBufferPointer(start: report, count: length))
                transport.queue.async {
                    transport.pendingContinuation?.resume(returning: bytes)
                    transport.pendingContinuation = nil
                }
            },
            context
        )
    }

    deinit {
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        reportBuffer.deallocate()
    }

    func send(_ packet: [UInt8]) async throws -> [UInt8] {
        try await withCheckedThrowingContinuation { continuation in
            queue.sync { self.pendingContinuation = continuation }
            let sendResult = packet.withUnsafeBufferPointer { ptr in
                IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, ptr.baseAddress!, ptr.count)
            }
            if sendResult != kIOReturnSuccess {
                queue.sync { self.pendingContinuation = nil }
                continuation.resume(throwing: DeviceTransportError.noDeviceFound)
            }
        }
    }
}
