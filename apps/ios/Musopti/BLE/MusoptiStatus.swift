import Foundation

struct MusoptiFirmwareVersion: Codable, Equatable {
    let major: UInt8
    let minor: UInt8
    let patch: UInt8

    var title: String {
        "\(major).\(minor).\(patch)"
    }
}

struct MusoptiStatus: Equatable {
    let version: UInt8
    let flags: UInt8
    let batteryPercentRaw: UInt8
    let deviceMode: MusoptiDeviceMode
    let exerciseType: MusoptiExerciseType
    let motionStateRaw: UInt8
    let sampleRateHz: UInt16
    let configRevision: UInt16
    let firmwareVersion: MusoptiFirmwareVersion

    var batteryPercent: Int? {
        isBatteryValid ? Int(batteryPercentRaw) : nil
    }

    var isBatteryValid: Bool {
        (flags & 0x01) != 0 && batteryPercentRaw != 0xFF
    }

    var isRecordingActive: Bool {
        (flags & 0x02) != 0
    }

    var isIMUSimulated: Bool {
        (flags & 0x04) != 0
    }

    var isDisplaySimulated: Bool {
        (flags & 0x08) != 0
    }

    var isAudioSimulated: Bool {
        (flags & 0x10) != 0
    }

    var motionPhase: MotionPhase {
        switch motionStateRaw {
        case 0: return .idle
        case 1: return .phaseA
        case 2: return .hold
        case 3: return .phaseB
        case 4: return .repComplete
        case 5: return .repInvalid
        default: return .idle
        }
    }

    static func parse(from data: Data) -> MusoptiStatus? {
        guard data.count == BLEConstants.statusPayloadSize else { return nil }
        guard data.readUInt8(at: 0) == 1 else { return nil }

        guard let flags = data.readUInt8(at: 1),
              let batteryPercentRaw = data.readUInt8(at: 2),
              let deviceModeRaw = data.readUInt8(at: 3),
              let deviceMode = MusoptiDeviceMode(rawValue: deviceModeRaw),
              let exerciseTypeRaw = data.readUInt8(at: 4),
              let exerciseType = MusoptiExerciseType(rawValue: exerciseTypeRaw),
              let motionStateRaw = data.readUInt8(at: 5),
              let sampleRateHz = data.readUInt16LE(at: 6),
              let configRevision = data.readUInt16LE(at: 8),
              let fwMajor = data.readUInt8(at: 10),
              let fwMinor = data.readUInt8(at: 11),
              let fwPatch = data.readUInt8(at: 12)
        else {
            return nil
        }

        return MusoptiStatus(
            version: 1,
            flags: flags,
            batteryPercentRaw: batteryPercentRaw,
            deviceMode: deviceMode,
            exerciseType: exerciseType,
            motionStateRaw: motionStateRaw,
            sampleRateHz: sampleRateHz,
            configRevision: configRevision,
            firmwareVersion: MusoptiFirmwareVersion(major: fwMajor, minor: fwMinor, patch: fwPatch)
        )
    }
}
