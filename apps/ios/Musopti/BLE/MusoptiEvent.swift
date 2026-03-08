import Foundation

enum MusoptiEventType: UInt8 {
    case stateChange = 0
    case repComplete = 1
    case holdResult = 2
    case sessionStart = 3
    case sessionStop = 4
}

enum MusoptiExerciseType: UInt8 {
    case generic = 0
    case benchPress = 1
    case squat = 2
    case deadlift = 3
    case custom = 4
}

enum MusoptiDeviceMode: UInt8 {
    case idle = 0
    case detection = 1
    case recording = 2
}

struct MusoptiEvent {
    let version: UInt8
    let eventType: MusoptiEventType
    let state: UInt8
    let flags: UInt8
    let repCount: UInt16
    let exerciseType: MusoptiExerciseType
    let deviceMode: MusoptiDeviceMode
    let holdDurationMs: UInt32

    var holdValid: Bool {
        (flags & 0x01) != 0
    }

    var phase: MotionPhase {
        switch state {
        case 0: return .idle
        case 1: return .phaseA
        case 2: return .hold
        case 3: return .phaseB
        case 4: return .repComplete
        case 5: return .repInvalid
        default: return .idle
        }
    }

    static func parse(from data: Data) -> MusoptiEvent? {
        guard data.count == BLEConstants.eventPayloadSize else { return nil }
        guard data.readUInt8(at: 0) == 2 else { return nil }

        guard let eventTypeRaw = data.readUInt8(at: 1),
              let eventType = MusoptiEventType(rawValue: eventTypeRaw),
              let state = data.readUInt8(at: 2),
              let flags = data.readUInt8(at: 3),
              let repCount = data.readUInt16LE(at: 4),
              let exerciseTypeRaw = data.readUInt8(at: 6),
              let exerciseType = MusoptiExerciseType(rawValue: exerciseTypeRaw),
              let deviceModeRaw = data.readUInt8(at: 7),
              let deviceMode = MusoptiDeviceMode(rawValue: deviceModeRaw),
              let holdDurationMs = data.readUInt32LE(at: 8)
        else { return nil }

        return MusoptiEvent(
            version: 2,
            eventType: eventType,
            state: state,
            flags: flags,
            repCount: repCount,
            exerciseType: exerciseType,
            deviceMode: deviceMode,
            holdDurationMs: holdDurationMs
        )
    }
}
