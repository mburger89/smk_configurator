#if canImport(CoreBluetooth)
import CoreBluetooth
import Foundation

/// Talks to the ESP32-C6 build's BLE HID Report ID 2 upload channel (see
/// Sources/componets/ble_helper.c in the SMK firmware repo) via
/// CoreBluetooth, using the standard HID-over-GATT service (0x1812) and the
/// Report Reference descriptor (0x2908) to find the right Report
/// characteristic among possibly several.
@MainActor
final class BLETransport: NSObject, DeviceTransport {
    private static let hidServiceUUID = CBUUID(string: "1812")
    private static let reportCharacteristicUUID = CBUUID(string: "2A4D")
    private static let reportReferenceDescriptorUUID = CBUUID(string: "2908")
    private static let targetReportID: UInt8 = 2
    private static let reportTypeInput: UInt8 = 0x01
    private static let reportTypeOutput: UInt8 = 0x02

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?   // Report ID 2, report type Output (0x02) — host writes commands here
    private var notifyCharacteristic: CBCharacteristic?  // Report ID 2, report type Input (0x01) — device sends ACK/NAK here
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var pendingContinuation: CheckedContinuation<[UInt8], Error>?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    /// Scans for, connects to, and locates the upload characteristic on the
    /// keyboard. Must complete before send(_:) is called.
    func connect() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.readyContinuation = continuation
            central.delegate = self
            if central.state == .poweredOn {
                central.scanForPeripherals(withServices: [Self.hidServiceUUID])
            }
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10s
                guard let self, let pending = self.readyContinuation else { return }
                self.readyContinuation = nil
                self.central.stopScan()
                pending.resume(throwing: DeviceTransportError.noDeviceFound)
            }
        }
    }

    func send(_ packet: [UInt8]) async throws -> [UInt8] {
        guard let peripheral, let writeCharacteristic else {
            throw DeviceTransportError.noDeviceFound
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.pendingContinuation = continuation
            peripheral.writeValue(Data(packet), for: writeCharacteristic, type: .withResponse)
        }
    }
}

extension BLETransport: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            central.scanForPeripherals(withServices: [Self.hidServiceUUID])
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        readyContinuation?.resume(throwing: DeviceTransportError.noDeviceFound)
        readyContinuation = nil
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.hidServiceUUID])
    }
}

extension BLETransport: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.hidServiceUUID }) else {
            readyContinuation?.resume(throwing: DeviceTransportError.noDeviceFound)
            readyContinuation = nil
            return
        }
        peripheral.discoverCharacteristics([Self.reportCharacteristicUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] where characteristic.uuid == Self.reportCharacteristicUUID {
            peripheral.discoverDescriptors(for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
        guard let descriptor = characteristic.descriptors?.first(where: { $0.uuid == Self.reportReferenceDescriptorUUID }) else {
            return
        }
        peripheral.readValue(for: descriptor)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
        guard let data = descriptor.value as? Data, data.count >= 2,
              data[0] == Self.targetReportID,
              let characteristic = descriptor.characteristic
        else { return }

        switch data[1] {
        case Self.reportTypeOutput:
            writeCharacteristic = characteristic
        case Self.reportTypeInput:
            notifyCharacteristic = characteristic
            peripheral.setNotifyValue(true, for: characteristic)
        default:
            return
        }

        if writeCharacteristic != nil && notifyCharacteristic != nil {
            readyContinuation?.resume(returning: ())
            readyContinuation = nil
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic === notifyCharacteristic, let data = characteristic.value else { return }
        pendingContinuation?.resume(returning: Array(data))
        pendingContinuation = nil
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            pendingContinuation?.resume(throwing: DeviceTransportError.transportFailure(error.localizedDescription))
            pendingContinuation = nil
        }
    }
}
#endif
