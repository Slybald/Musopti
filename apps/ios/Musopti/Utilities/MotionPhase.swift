import Foundation

enum MotionPhase: String, CaseIterable {
    case idle
    case phaseA = "Phase A"
    case hold = "Hold"
    case phaseB = "Phase B"
    case repComplete = "Rep Complete"
    case repInvalid = "Rep Invalid"

    var label: String {
        switch self {
        case .idle:
            return "Idle"
        default:
            return rawValue
        }
    }
}
