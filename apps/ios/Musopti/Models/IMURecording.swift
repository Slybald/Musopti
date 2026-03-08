import Foundation
import SwiftData

@Model
final class IMURecording {
    @Attribute(.unique) var id: UUID
    var exerciseID: UUID?
    var exerciseName: String
    var sampleRateHz: Int
    var startedAt: Date
    var finishedAt: Date?
    var sampleCount: Int
    var filePath: String
    var notes: String?

    init(id: UUID = UUID(), exerciseID: UUID? = nil, exerciseName: String, sampleRateHz: Int = 100, startedAt: Date = .now, finishedAt: Date? = nil, sampleCount: Int = 0, filePath: String = "", notes: String? = nil) {
        self.id = id
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.sampleRateHz = sampleRateHz
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.sampleCount = sampleCount
        self.filePath = filePath
        self.notes = notes
    }

    var duration: TimeInterval? {
        guard let end = finishedAt else { return nil }
        return end.timeIntervalSince(startedAt)
    }

    var estimatedFileSize: Int {
        sampleCount * 28 // 6 floats + 1 uint32 per sample
    }
}
