import Foundation
import SwiftData

@Model
final class Exercise {
    @Attribute(.unique) var id: UUID
    var name: String
    var category: ExerciseCategory
    var muscleGroup: String
    var equipmentType: String
    var isBuiltIn: Bool
    var iconName: String
    var detectionProfile: DetectionProfile
    var userID: String?

    init(id: UUID = UUID(), name: String, category: ExerciseCategory, muscleGroup: String, equipmentType: String, isBuiltIn: Bool = true, iconName: String = "", detectionProfile: DetectionProfile = .generic, userID: String? = nil) {
        self.id = id
        self.name = name
        self.category = category
        self.muscleGroup = muscleGroup
        self.equipmentType = equipmentType
        self.isBuiltIn = isBuiltIn
        self.iconName = iconName
        self.detectionProfile = detectionProfile
        self.userID = userID
    }
}
