#if canImport(CoreBluetooth)
import Testing
@testable import SMKConfigurator

@Suite("BLEConnectionState distinguishes the states the DEV pane must show")
struct BLEConnectionStateTests {
    @Test("only .ready counts as usable for an upload")
    func readiness() {
        #expect(BLEConnectionState.ready.isReady)
        #expect(!BLEConnectionState.connected.isReady)
        #expect(!BLEConnectionState.idle.isReady)
        #expect(!BLEConnectionState.failed("nope").isReady)
    }

    @Test("connected-but-not-ready reads differently from not connected")
    func summariesAreDistinct() {
        // A board whose service is missing is a UUID mismatch, not an absent
        // keyboard, and the pane must not conflate the two.
        #expect(BLEConnectionState.connected.summary != BLEConnectionState.idle.summary)
        #expect(BLEConnectionState.ready.summary != BLEConnectionState.connected.summary)
    }
}
#endif
