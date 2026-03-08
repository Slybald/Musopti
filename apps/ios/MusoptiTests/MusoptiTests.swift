import Foundation
import Testing
@testable import MusoptiCore

@Test func bleUUIDs_matchSpec() async throws {
    #expect(BLEConstants.deviceName == "Musopti")
    #expect(BLEConstants.serviceUUID.uuidString == "4D55534F-5054-4900-0001-000000000000")
    #expect(BLEConstants.eventCharUUID.uuidString == "4D55534F-5054-4900-0001-000000000001")
    #expect(BLEConstants.configCharUUID.uuidString == "4D55534F-5054-4900-0001-000000000002")
    #expect(BLEConstants.rawDataCharUUID.uuidString == "4D55534F-5054-4900-0001-000000000003")
    #expect(BLEConstants.statusCharUUID.uuidString == "4D55534F-5054-4900-0001-000000000004")
}

@Test func parseEvent_v2_littleEndian() async throws {
    // version=2, eventType=repComplete(1), state=phaseB(3), flags=holdValid(1)
    // repCount=42, exerciseType=benchPress(1), deviceMode=detection(1), holdDurationMs=3000
    let bytes: [UInt8] = [
        2, 1, 3, 0x01,
        0x2a, 0x00,
        0x01,
        0x01,
        0xb8, 0x0b, 0x00, 0x00,
    ]
    let data = Data(bytes)
    let evt = MusoptiEvent.parse(from: data)
    #expect(evt != nil)
    #expect(evt?.version == 2)
    #expect(evt?.eventType == .repComplete)
    #expect(evt?.state == 3)
    #expect(evt?.holdValid == true)
    #expect(evt?.repCount == 42)
    #expect(evt?.exerciseType == .benchPress)
    #expect(evt?.deviceMode == .detection)
    #expect(evt?.holdDurationMs == 3000)
}

@Test func parseEvent_rejectsWrongVersion() async throws {
    var bytes = [UInt8](repeating: 0, count: BLEConstants.eventPayloadSize)
    bytes[0] = 1
    let evt = MusoptiEvent.parse(from: Data(bytes))
    #expect(evt == nil)
}

@Test func config_roundTrip_v1() async throws {
    let cfg = MusoptiConfig(
        deviceMode: .recording,
        exerciseType: .squat,
        holdTargetMs: 2500,
        holdToleranceMs: 150,
        minRepDurationMs: 900,
        sampleRateHz: 100
    )
    let data = cfg.toData()
    #expect(data.count == BLEConstants.configPayloadSize)
    let parsed = MusoptiConfig.parse(from: data)
    #expect(parsed?.deviceMode == .recording)
    #expect(parsed?.exerciseType == .squat)
    #expect(parsed?.holdTargetMs == 2500)
    #expect(parsed?.holdToleranceMs == 150)
    #expect(parsed?.minRepDurationMs == 900)
    #expect(parsed?.sampleRateHz == 100)
}

@Test func parseStatus_v1_littleEndian() async throws {
    let bytes: [UInt8] = [
        1,
        0x06,
        0xFF,
        MusoptiDeviceMode.recording.rawValue,
        MusoptiExerciseType.benchPress.rawValue,
        0x02,
        0x64, 0x00,
        0x05, 0x00,
        1, 2, 3,
        0x00,
    ]

    let status = MusoptiStatus.parse(from: Data(bytes))
    #expect(status != nil)
    #expect(status?.version == 1)
    #expect(status?.isBatteryValid == false)
    #expect(status?.isRecordingActive == true)
    #expect(status?.isIMUSimulated == true)
    #expect(status?.deviceMode == .recording)
    #expect(status?.exerciseType == .benchPress)
    #expect(status?.motionPhase == .hold)
    #expect(status?.sampleRateHz == 100)
    #expect(status?.configRevision == 5)
    #expect(status?.firmwareVersion.title == "1.2.3")
}

@Test func syncEvaluator_detectsStatusMismatch() async throws {
    let sent = MusoptiConfig(
        deviceMode: .recording,
        exerciseType: .squat,
        holdTargetMs: 0,
        holdToleranceMs: 0,
        minRepDurationMs: 800,
        sampleRateHz: 200
    )
    let readBack = sent
    let mismatchedStatus = MusoptiStatus(
        version: 1,
        flags: 0,
        batteryPercentRaw: 0xFF,
        deviceMode: .recording,
        exerciseType: .squat,
        motionStateRaw: 0,
        sampleRateHz: 100,
        configRevision: 7,
        firmwareVersion: MusoptiFirmwareVersion(major: 1, minor: 0, patch: 0)
    )

    #expect(BLESyncEvaluator.isInSync(sent: sent, readBack: readBack, status: mismatchedStatus) == false)
    #expect(BLESyncEvaluator.syncErrorMessage(sent: sent, readBack: readBack, status: mismatchedStatus) != nil)
}
