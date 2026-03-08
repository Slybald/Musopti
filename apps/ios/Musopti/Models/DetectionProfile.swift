import Foundation

struct DetectionProfile: Codable, Equatable {
    var firmwareExerciseType: UInt8
    var requireHold: Bool
    var holdTargetMs: UInt16
    var holdToleranceMs: UInt16
    var minRepDurationMs: UInt16

    static let generic = DetectionProfile(firmwareExerciseType: 0, requireHold: false, holdTargetMs: 0, holdToleranceMs: 0, minRepDurationMs: 600)
    static let benchPress = DetectionProfile(firmwareExerciseType: 1, requireHold: true, holdTargetMs: 3000, holdToleranceMs: 200, minRepDurationMs: 1000)
    static let squat = DetectionProfile(firmwareExerciseType: 2, requireHold: false, holdTargetMs: 0, holdToleranceMs: 0, minRepDurationMs: 800)
    static let deadlift = DetectionProfile(firmwareExerciseType: 3, requireHold: false, holdTargetMs: 0, holdToleranceMs: 0, minRepDurationMs: 1200)
}
