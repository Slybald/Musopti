import SwiftUI

extension ExerciseCategory {
    var accentColor: Color {
        switch self {
        case .chest:
            return MusoptiTheme.warning
        case .back:
            return MusoptiTheme.phaseA
        case .legs:
            return MusoptiTheme.valid
        case .shoulders:
            return MusoptiTheme.hold
        case .arms:
            return MusoptiTheme.phaseB
        case .core:
            return MusoptiTheme.accent
        case .cardio:
            return MusoptiTheme.textSecondary
        case .custom:
            return MusoptiTheme.accent
        }
    }
}

extension Exercise {
    var resolvedIconName: String {
        iconName.isEmpty ? category.iconName : iconName
    }

    var equipmentDisplayName: String {
        switch normalizedEquipmentType {
        case "":
            return "No equipment"
        case "barbell":
            return "Barbell"
        case "dumbbell":
            return "Dumbbell"
        case "machine":
            return "Machine"
        case "smith machine":
            return "Smith Machine"
        case "cable":
            return "Cable"
        case "bodyweight":
            return "Bodyweight"
        case "kettlebell":
            return "Kettlebell"
        default:
            return equipmentType.capitalized
        }
    }

    var equipmentBadgeText: String? {
        switch normalizedEquipmentType {
        case "barbell":
            return "BB"
        case "dumbbell":
            return "DB"
        case "machine":
            return "MA"
        case "smith machine":
            return "SM"
        case "cable":
            return "CA"
        case "bodyweight":
            return "BW"
        case "kettlebell":
            return "KB"
        default:
            return nil
        }
    }

    static func defaultIconName(for category: ExerciseCategory) -> String {
        category.iconName
    }

    private var normalizedEquipmentType: String {
        equipmentType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct ExerciseIconView: View {
    let symbolName: String
    let category: ExerciseCategory
    let badgeText: String?
    var size: CGFloat = 44

    init(exercise: Exercise, size: CGFloat = 44) {
        self.symbolName = exercise.resolvedIconName
        self.category = exercise.category
        self.badgeText = exercise.equipmentBadgeText
        self.size = size
    }

    init(symbolName: String, category: ExerciseCategory, badgeText: String? = nil, size: CGFloat = 44) {
        self.symbolName = symbolName
        self.category = category
        self.badgeText = badgeText
        self.size = size
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: max(12, size * 0.28), style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            category.accentColor.opacity(0.34),
                            MusoptiTheme.cardBackground,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: max(12, size * 0.28), style: .continuous)
                        .stroke(category.accentColor.opacity(0.5), lineWidth: 1)
                )

            Image(systemName: symbolName)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(MusoptiTheme.textPrimary)

            if let badgeText, !badgeText.isEmpty {
                Text(badgeText)
                    .font(.system(size: max(9, size * 0.18), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, max(5, size * 0.12))
                    .padding(.vertical, max(3, size * 0.05))
                    .background(category.accentColor)
                    .clipShape(Capsule())
                    .padding(4)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
