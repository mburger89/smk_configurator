#if canImport(CoreBluetooth)
import CoreBluetooth
import Testing
@testable import SMKConfigurator

/// Deliberately a change-detector. These UUIDs are generated into two repos
/// from ~/esp/SMK/ble_upload_uuids.json; a regeneration or hand-edit that
/// changes one silently produces a keyboard this app can never find, with no
/// error anywhere. Failing here is the cheapest place to notice.
@Suite("BLE upload service UUIDs match the firmware's generated constants")
struct BLEUploadUUIDsTests {
    @Test("service UUID is unchanged")
    func serviceUUID() {
        #expect(BLEUploadUUIDs.service.uuidString == "DA227673-007D-4BE6-A602-BC27421945FC")
    }

    @Test("packet write characteristic UUID is unchanged")
    func packetUUID() {
        #expect(BLEUploadUUIDs.packet.uuidString == "3A877283-CAFD-4716-8671-148B32475E97")
    }

    @Test("response notify characteristic UUID is unchanged")
    func responseUUID() {
        #expect(BLEUploadUUIDs.response.uuidString == "C975356B-1B48-4871-A8A6-FB1155381A8F")
    }
}
#endif
