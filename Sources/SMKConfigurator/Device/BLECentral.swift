#if canImport(CoreBluetooth)
import CoreBluetooth
import Foundation

/// What the DEV pane shows, and what gates an upload. `.connected` means a
/// GATT link exists but the upload service or one of its characteristics is
/// missing -- the exact symptom of a firmware/app UUID mismatch, kept
/// distinct from `.idle` so nobody has to guess which they have.
enum BLEConnectionState: Equatable {
    case idle
    case searching
    case connecting
    case connected
    case ready
    case failed(String)

    var isReady: Bool { self == .ready }

    var summary: String {
        switch self {
        case .idle: return "Not connected"
        case .searching: return "Searching…"
        case .connecting: return "Connecting…"
        case .connected: return "Connected — upload service missing"
        case .ready: return "Ready"
        case .failed(let why): return "Failed: \(why)"
        }
    }
}

/// The single shared CoreBluetooth session for the upload service. Owns the
/// one `CBCentralManager` in the app -- two managers would scan against each
/// other and fight over the same peripheral. Used by BLETransport (upload),
/// EditorState (device status), and the DEV pane's live monitor.
@MainActor
final class BLECentral: NSObject {
    static let shared = BLECentral()

    private(set) var state: BLEConnectionState = .idle
    private(set) var peripheralName: String?
    private(set) var rssi: Int?
    /// Largest single write the link will take, from
    /// `maximumWriteValueLength(for: .withResponse)`. Purely diagnostic --
    /// packets are always 32 bytes -- but it is the fastest way to tell a
    /// healthy link from a barely-negotiated one.
    private(set) var mtu: Int?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var packetCharacteristic: CBCharacteristic?
    private var responseCharacteristic: CBCharacteristic?
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var pendingContinuation: CheckedContinuation<[UInt8], Error>?
    /// The single in-flight connection attempt, if any. A second caller
    /// arriving while one attempt is already running (e.g. a periodic
    /// monitor overlapping a user-initiated connect) awaits this same task
    /// instead of opening a second continuation over `readyContinuation` --
    /// which would strand the first caller forever and let the first
    /// attempt's timeout resolve the second attempt instead.
    private var connectTask: Task<Void, Error>?
    /// Stamps identifying which connect/send a timeout task belongs to.
    /// Every timeout is both cancelled when its own operation finishes and
    /// gated on its stamp still being the current one, so a timer armed by
    /// an operation that has already ended can never resume the
    /// continuation of a *later* one (see the timeout tasks below).
    private var connectGeneration: UInt64 = 0
    private var sendGeneration: UInt64 = 0

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    /// Resolves only once notifications are live -- a packet written before
    /// the subscription is active gets a response nobody is listening for.
    ///
    /// One continuation, one 10s timeout, covering both discovery paths
    /// below -- arming a second timeout per path would let the continuation
    /// be resumed twice (a trap) if both fired. Concurrent callers coalesce
    /// onto the single in-flight `connectTask` rather than each opening
    /// their own continuation: every caller means "ensure we're connected",
    /// so they can all share one attempt and one outcome.
    func connect() async throws {
        if state.isReady { return }
        if let connectTask {
            try await connectTask.value
            return
        }
        let task = Task<Void, Error> { [self] in
            defer { self.connectTask = nil }
            // Scanning before the manager is powered on is dropped on the
            // floor by Core Bluetooth (logged as API MISUSE, never queued),
            // so an unpowered/unauthorized radio would otherwise burn the
            // full 10s timeout and then look exactly like "no keyboard
            // here". Fail fast with the real reason instead.
            try await self.requirePoweredOn()
            self.connectGeneration &+= 1
            let generation = self.connectGeneration
            // Held so the attempt that armed it can cancel it the moment it
            // finishes, however it finishes -- see the stamp check below
            // for why an uncancelled straggler still can't do harm.
            var timeout: Task<Void, Never>?
            defer { timeout?.cancel() }
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                self.readyContinuation = c
                timeout = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    guard !Task.isCancelled, let self,
                          self.connectGeneration == generation,
                          let pending = self.readyContinuation else { return }
                    self.readyContinuation = nil
                    self.central.stopScan()
                    self.state = .idle
                    pending.resume(throwing: DeviceTransportError.noDeviceFound)
                }
                // Fast path: a bonded keyboard in use is connected to the
                // system and NOT advertising, so a scan would miss it
                // exactly when it is working. This only finds it because we
                // match a custom service; Core Bluetooth would never report
                // a HID match here.
                if let known = self.central.retrieveConnectedPeripherals(
                    withServices: [BLEUploadUUIDs.service]
                ).first {
                    self.peripheral = known
                    known.delegate = self
                    self.state = .connecting
                    self.central.connect(known)
                } else {
                    self.state = .searching
                    self.central.scanForPeripherals(withServices: [BLEUploadUUIDs.service])
                }
            }
        }
        connectTask = task
        try await task.value
    }

    func send(_ packet: [UInt8]) async throws -> [UInt8] {
        guard let peripheral, let packetCharacteristic else {
            throw DeviceTransportError.noDeviceFound
        }
        // Unlike connect(), overlapping sends carry different packets and
        // cannot share an outcome -- coalescing would silently deliver one
        // call's response to the other. Surface it as a caller bug instead.
        guard pendingContinuation == nil else {
            throw DeviceTransportError.transportFailure("a packet is already in flight")
        }
        sendGeneration &+= 1
        let generation = sendGeneration
        // A ~4 KB keymap is ~150 of these round trips back to back. A
        // fire-and-forget timer that outlives its own packet would fire
        // mid-upload and fail whichever packet was then in flight (most
        // often COMMIT, reporting failure for an upload the firmware had
        // already committed), so each timer is cancelled by the send that
        // armed it and, belt and braces, refuses to act unless its stamp is
        // still current.
        var timeout: Task<Void, Never>?
        defer { timeout?.cancel() }
        return try await withCheckedThrowingContinuation { c in
            self.pendingContinuation = c
            peripheral.writeValue(Data(packet), for: packetCharacteristic, type: .withResponse)
            timeout = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled, let self,
                      self.sendGeneration == generation,
                      let pending = self.pendingContinuation else { return }
                self.pendingContinuation = nil
                pending.resume(throwing: DeviceTransportError.transportFailure(
                    "timed out waiting for a response packet"))
            }
        }
    }

    func readRSSI() {
        peripheral?.readRSSI()
    }

    /// Returns once the manager is `.poweredOn`; throws a described
    /// `.transportFailure` otherwise.
    ///
    /// `.unknown`/`.resetting` are startup states, not failures: a
    /// `CBCentralManager` created moments ago reports `.unknown` until its
    /// first `centralManagerDidUpdateState` lands, so a connect() issued
    /// right after launch (the DEV pane's monitor does exactly that) has to
    /// wait rather than fail. Bounded, because a stack that never settles
    /// must not hang the caller either.
    private func requirePoweredOn() async throws {
        for _ in 0..<60 {
            guard central.state == .unknown || central.state == .resetting else { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        guard central.state == .poweredOn else {
            let why = Self.unavailableReason(for: central.state)
            state = .failed(why)
            throw DeviceTransportError.transportFailure(why)
        }
    }

    /// User-facing text for every non-`.poweredOn` manager state. These are
    /// the failures that are otherwise indistinguishable from "no keyboard
    /// in range", including the one an app bundle missing
    /// `NSBluetoothAlwaysUsageDescription` produces (`.unauthorized`).
    static func unavailableReason(for managerState: CBManagerState) -> String {
        switch managerState {
        case .poweredOn: return "Bluetooth is available"
        case .poweredOff: return "Bluetooth is off — turn it on in System Settings"
        case .unauthorized:
            return "Bluetooth access was denied — allow it in System Settings › Privacy & Security › Bluetooth"
        case .unsupported: return "this machine has no Bluetooth LE radio"
        case .resetting: return "the Bluetooth stack is resetting — try again in a moment"
        case .unknown: return "the Bluetooth stack has not finished starting up"
        @unknown default: return "Bluetooth is unavailable"
        }
    }
}

extension BLECentral: @preconcurrency CBCentralManagerDelegate {
    // The only non-optional method of this protocol. connect() polls
    // `central.state` itself (see requirePoweredOn) rather than being driven
    // from here, so this exists to catch the radio going away *after* a
    // connect: nothing in flight can complete once the manager leaves
    // .poweredOn, and the DEV pane would otherwise sit on a stale "Ready".
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn, .unknown, .resetting:
            // .unknown/.resetting are startup/transient states, not
            // failures -- reporting them would make the DEV pane flash a
            // scary string during the manager's normal cold start.
            // .poweredOn deliberately leaves `state` alone: the next
            // connect() sets it, and clearing here would also erase an
            // unrelated .failed (e.g. "upload service not found").
            break
        case .poweredOff, .unauthorized, .unsupported:
            let why = Self.unavailableReason(for: central.state)
            state = .failed(why)
            packetCharacteristic = nil
            responseCharacteristic = nil
            pendingContinuation?.resume(throwing: DeviceTransportError.transportFailure(why))
            pendingContinuation = nil
            readyContinuation?.resume(throwing: DeviceTransportError.transportFailure(why))
            readyContinuation = nil
        @unknown default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        central.stopScan()
        state = .connecting
        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        state = .connected
        peripheralName = peripheral.name
        mtu = peripheral.maximumWriteValueLength(for: .withResponse)
        peripheral.discoverServices([BLEUploadUUIDs.service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        state = .idle
        readyContinuation?.resume(throwing: DeviceTransportError.noDeviceFound)
        readyContinuation = nil
    }

    // The old transport left an in-flight continuation suspended forever if
    // the board vanished mid-upload.
    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        packetCharacteristic = nil
        responseCharacteristic = nil
        rssi = nil
        mtu = nil
        peripheralName = nil
        state = .idle
        pendingContinuation?.resume(throwing:
            DeviceTransportError.transportFailure("disconnected mid-upload"))
        pendingContinuation = nil
        readyContinuation?.resume(throwing: DeviceTransportError.noDeviceFound)
        readyContinuation = nil
    }
}

extension BLECentral: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == BLEUploadUUIDs.service }) else {
            readyContinuation?.resume(throwing: DeviceTransportError.transportFailure(
                "upload service \(BLEUploadUUIDs.service.uuidString) not found"))
            readyContinuation = nil
            return
        }
        peripheral.discoverCharacteristics([BLEUploadUUIDs.packet, BLEUploadUUIDs.response], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case BLEUploadUUIDs.packet:
                packetCharacteristic = characteristic
            case BLEUploadUUIDs.response:
                responseCharacteristic = characteristic
            default:
                break
            }
        }
        guard packetCharacteristic != nil else {
            readyContinuation?.resume(throwing: DeviceTransportError.transportFailure(
                "packet characteristic \(BLEUploadUUIDs.packet.uuidString) not found"))
            readyContinuation = nil
            return
        }
        guard let responseCharacteristic else {
            readyContinuation?.resume(throwing: DeviceTransportError.transportFailure(
                "response characteristic \(BLEUploadUUIDs.response.uuidString) not found"))
            readyContinuation = nil
            return
        }
        peripheral.setNotifyValue(true, for: responseCharacteristic)
    }

    // Ready means *notifications are live*, not merely "characteristic
    // found". A packet written before the subscription is active gets a
    // response with nobody listening, and the upload hangs.
    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard characteristic.uuid == BLEUploadUUIDs.response else { return }
        if let error {
            state = .failed(error.localizedDescription)
            readyContinuation?.resume(throwing:
                DeviceTransportError.transportFailure(error.localizedDescription))
        } else {
            state = .ready
            readyContinuation?.resume(returning: ())
        }
        readyContinuation = nil
    }

    // Guarded on identity *and* error. Without the identity check any other
    // characteristic's update would be handed to a waiting send() as its
    // response; without the error check a failed notification resumes with
    // an empty payload, which the upload protocol reads as a well-formed
    // NAK rather than as the transport failure it actually is.
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == BLEUploadUUIDs.response else { return }
        guard let pending = pendingContinuation else { return }
        pendingContinuation = nil
        if let error {
            pending.resume(throwing: DeviceTransportError.transportFailure(error.localizedDescription))
        } else {
            pending.resume(returning: Array(characteristic.value ?? Data()))
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        rssi = RSSI.intValue
    }
}
#endif
