import Foundation
import SwiftData

@Model
final class WorkoutSession {
    @Attribute(.unique) var id: UUID
    var templateID: UUID?
    var templateName: String?
    var startedAt: Date
    var finishedAt: Date?
    var exercises: [ExerciseLog]
    var notes: String?

    init(id: UUID = UUID(), templateID: UUID? = nil, templateName: String? = nil, startedAt: Date = .now, finishedAt: Date? = nil, exercises: [ExerciseLog] = [], notes: String? = nil) {
        self.id = id
        self.templateID = templateID
        self.templateName = templateName
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.exercises = exercises
        self.notes = notes
    }

    var totalSets: Int {
        exercises.reduce(0) { $0 + $1.sets.count }
    }

    var totalReps: Int {
        exercises.reduce(0) { $0 + $1.sets.reduce(0) { $0 + $1.reps } }
    }

    var totalVolume: Double {
        exercises.reduce(0.0) { total, log in
            total + log.sets.reduce(0.0) { $0 + Double($1.reps) * ($1.weightKg ?? 0) }
        }
    }

    var duration: TimeInterval? {
        guard let end = finishedAt else { return nil }
        return end.timeIntervalSince(startedAt)
    }
}
