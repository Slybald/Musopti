import Testing
@testable import Musopti

struct BLESyncEvaluatorTests {
    @Test func syncEvaluator_acceptsMatchingReadBackAndStatus() async throws {
        let config = MusoptiConfig(
            deviceMode: .recording,
            exerciseType: .deadlift,
            holdTargetMs: 0,
            holdToleranceMs: 0,
            minRepDurationMs: 1200,
            sampleRateHz: 200
        )
        let status = MusoptiStatus(
            version: 1,
            flags: 0x02,
            batteryPercentRaw: 0xFF,
            deviceMode: .recording,
            exerciseType: .deadlift,
            motionStateRaw: 0,
            sampleRateHz: 200,
            configRevision: 9,
            firmwareVersion: MusoptiFirmwareVersion(major: 1, minor: 0, patch: 0)
        )

        #expect(BLESyncEvaluator.isInSync(sent: config, readBack: config, status: status))
        #expect(BLESyncEvaluator.syncErrorMessage(sent: config, readBack: config, status: status) == nil)
    }
}
