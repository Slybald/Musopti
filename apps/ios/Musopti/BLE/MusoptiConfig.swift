import Foundation

struct MusoptiConfig: Equatable {
    let deviceMode: MusoptiDeviceMode
    let exerciseType: MusoptiExerciseType
    let holdTargetMs: UInt16
    let holdToleranceMs: UInt16
    let minRepDurationMs: UInt16
    let sampleRateHz: UInt16

    func toData() -> Data {
        var data = Data()
        data.append(1) // version
        data.append(deviceMode.rawValue)
        data.append(exerciseType.rawValue)
        data.append(0) // reserved
        data.append(holdTargetMs.littleEndianData)
        data.append(holdToleranceMs.littleEndianData)
        data.append(minRepDurationMs.littleEndianData)
        data.append(sampleRateHz.littleEndianData)
        return data
    }

    static func parse(from data: Data) -> MusoptiConfig? {
        guard data.count == BLEConstants.configPayloadSize else { return nil }
        guard data.readUInt8(at: 0) == 1 else { return nil }

        guard let deviceModeRaw = data.readUInt8(at: 1),
              let deviceMode = MusoptiDeviceMode(rawValue: deviceModeRaw),
              let exerciseTypeRaw = data.readUInt8(at: 2),
              let exerciseType = MusoptiExerciseType(rawValue: exerciseTypeRaw),
              let holdTargetMs = data.readUInt16LE(at: 4),
              let holdToleranceMs = data.readUInt16LE(at: 6),
              let minRepDurationMs = data.readUInt16LE(at: 8),
              let sampleRateHz = data.readUInt16LE(at: 10)
        else { return nil }

        return MusoptiConfig(
            deviceMode: deviceMode,
            exerciseType: exerciseType,
            holdTargetMs: holdTargetMs,
            holdToleranceMs: holdToleranceMs,
            minRepDurationMs: minRepDurationMs,
            sampleRateHz: sampleRateHz
        )
    }

    static let defaultDetection = MusoptiConfig(
        deviceMode: .detection,
        exerciseType: .generic,
        holdTargetMs: 0,
        holdToleranceMs: 0,
        minRepDurationMs: 600,
        sampleRateHz: 100
    )
}
