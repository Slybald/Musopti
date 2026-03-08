import Foundation

enum ExerciseCategory: String, Codable, CaseIterable, Identifiable {
    case chest, back, legs, shoulders, arms, core, cardio, custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chest: return "Chest"
        case .back: return "Back"
        case .legs: return "Legs"
        case .shoulders: return "Shoulders"
        case .arms: return "Arms"
        case .core: return "Core"
        case .cardio: return "Cardio"
        case .custom: return "Custom"
        }
    }

    var iconName: String {
        switch self {
        case .chest: return "figure.strengthtraining.traditional"
        case .back: return "figure.rower"
        case .legs: return "figure.walk"
        case .shoulders: return "figure.arms.open"
        case .arms: return "figure.boxing"
        case .core: return "figure.core.training"
        case .cardio: return "figure.run"
        case .custom: return "star"
        }
    }
}
