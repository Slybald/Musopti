import Foundation

struct SetLog: Codable, Identifiable, Equatable {
    var id: UUID
    var setNumber: Int
    var reps: Int
    var weightKg: Double?
    var holdDurations: [UInt32]
    var holdValids: [Bool]
    var repTimestamps: [Date]
    var startedAt: Date
    var finishedAt: Date
    var restDurationSec: Double?

    init(id: UUID = UUID(), setNumber: Int, reps: Int, weightKg: Double? = nil, holdDurations: [UInt32] = [], holdValids: [Bool] = [], repTimestamps: [Date] = [], startedAt: Date = .now, finishedAt: Date = .now, restDurationSec: Double? = nil) {
        self.id = id
        self.setNumber = setNumber
        self.reps = reps
        self.weightKg = weightKg
        self.holdDurations = holdDurations
        self.holdValids = holdValids
        self.repTimestamps = repTimestamps
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.restDurationSec = restDurationSec
    }
}
