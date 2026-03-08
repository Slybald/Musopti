import CoreBluetooth
import Testing
@testable import Musopti

struct RecordingPreflightTests {
    @Test func preflight_requiresReadyDevice() async throws {
        var status = DeviceStatus.placeholder
        status.bluetoothState = .poweredOn

        let issue = RecordingPreflightEvaluator.evaluate(
            sampleRateHz: 100,
            bluetoothState: .poweredOn,
            deviceStatus: status
        )

        #expect(issue == .deviceNotReady)
    }

    @Test func preflight_rejectsUnsupportedRate() async throws {
        var status = DeviceStatus.placeholder
        status.connectionState = .ready
        status.bluetoothState = .poweredOn

        let issue = RecordingPreflightEvaluator.evaluate(
            sampleRateHz: 125,
            bluetoothState: .poweredOn,
            deviceStatus: status
        )

        #expect(issue == .unsupportedSampleRate)
    }

    @Test func preflight_acceptsReadyDevice() async throws {
        var status = DeviceStatus.placeholder
        status.connectionState = .ready
        status.bluetoothState = .poweredOn

        let issue = RecordingPreflightEvaluator.evaluate(
            sampleRateHz: 200,
            bluetoothState: .poweredOn,
            deviceStatus: status
        )

        #expect(issue == nil)
    }
}
