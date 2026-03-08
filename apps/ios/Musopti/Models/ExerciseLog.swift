import Foundation

struct ExerciseLog: Codable, Identifiable, Equatable {
    var id: UUID
    var exerciseID: UUID
    var exerciseName: String
    var order: Int
    var sets: [SetLog]

    init(id: UUID = UUID(), exerciseID: UUID, exerciseName: String = "", order: Int = 0, sets: [SetLog] = []) {
        self.id = id
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.order = order
        self.sets = sets
    }
}
