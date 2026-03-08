import Foundation
import SwiftData

struct WorkoutTemplateEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var exerciseID: UUID
    var exerciseName: String
    var targetSets: Int
    var targetReps: Int
    var order: Int

    init(id: UUID = UUID(), exerciseID: UUID, exerciseName: String = "", targetSets: Int = 3, targetReps: Int = 10, order: Int = 0) {
        self.id = id
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.order = order
    }
}

@Model
final class WorkoutTemplate {
    @Attribute(.unique) var id: UUID
    var name: String
    var exercises: [WorkoutTemplateEntry]
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, exercises: [WorkoutTemplateEntry] = [], createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id
        self.name = name
        self.exercises = exercises
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
