import Foundation
import Testing
@testable import MusoptiCore

private func littleEndianBytes(for value: Float) -> [UInt8] {
    withUnsafeBytes(of: value.bitPattern.littleEndian) { Array($0) }
}

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
        0x1E,
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
    #expect(status?.isDisplaySimulated == true)
    #expect(status?.isAudioSimulated == true)
    #expect(status?.deviceMode == .recording)
    #expect(status?.exerciseType == .benchPress)
    #expect(status?.motionPhase == .hold)
    #expect(status?.sampleRateHz == 100)
    #expect(status?.configRevision == 5)
    #expect(status?.firmwareVersion.title == "1.2.3")
}

@Test func readFloat32LE_handlesUnalignedOffset() async throws {
    let data = Data([0xAA, 0x55] + littleEndianBytes(for: 1.5))

    let value = data.readFloat32LE(at: 2)

    #expect(value != nil)
    #expect(abs((value ?? 0) - 1.5) < 0.0001)
}

@Test func parseRawDataPacket_withTwoByteHeader() async throws {
    let bytes: [UInt8] = [
        1, 1,
    ] + littleEndianBytes(for: 1.5)
      + littleEndianBytes(for: -2.25)
      + littleEndianBytes(for: 9.81)
      + littleEndianBytes(for: 0.125)
      + littleEndianBytes(for: -0.5)
      + littleEndianBytes(for: 3.0)
      + [0x2A, 0x00, 0x00, 0x00]

    let samples = RawDataParser.parse(from: Data(bytes))

    #expect(samples?.count == 1)
    #expect(abs((samples?.first?.accelX ?? 0) - 1.5) < 0.0001)
    #expect(abs((samples?.first?.accelY ?? 0) - (-2.25)) < 0.0001)
    #expect(abs((samples?.first?.accelZ ?? 0) - 9.81) < 0.0001)
    #expect(abs((samples?.first?.gyroX ?? 0) - 0.125) < 0.0001)
    #expect(abs((samples?.first?.gyroY ?? 0) - (-0.5)) < 0.0001)
    #expect(abs((samples?.first?.gyroZ ?? 0) - 3.0) < 0.0001)
    #expect(samples?.first?.timestampMs == 42)
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
