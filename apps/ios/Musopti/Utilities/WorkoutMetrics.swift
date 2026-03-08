import Foundation

extension SetLog {
    var volumeKg: Double {
        Double(reps) * (weightKg ?? 0)
    }

    var averageHoldMs: Double? {
        guard !holdDurations.isEmpty else { return nil }
        return Double(holdDurations.reduce(0, +)) / Double(holdDurations.count)
    }

    var holdSuccessRate: Double? {
        guard !holdValids.isEmpty else { return nil }
        let validCount = holdValids.filter(\.self).count
        return Double(validCount) / Double(holdValids.count)
    }
}

extension ExerciseLog {
    var totalReps: Int {
        sets.reduce(0) { $0 + $1.reps }
    }

    var totalVolume: Double {
        sets.reduce(0) { $0 + $1.volumeKg }
    }

    var averageHoldMs: Double? {
        let holds = sets.flatMap(\.holdDurations)
        guard !holds.isEmpty else { return nil }
        return Double(holds.reduce(0, +)) / Double(holds.count)
    }

    var holdSuccessRate: Double? {
        let values = sets.flatMap(\.holdValids)
        guard !values.isEmpty else { return nil }
        return Double(values.filter(\.self).count) / Double(values.count)
    }

    var heaviestWeightKg: Double? {
        sets.compactMap(\.weightKg).max()
    }
}

extension WorkoutSession {
    var holdSuccessRate: Double? {
        let values = exercises.flatMap { $0.sets.flatMap(\.holdValids) }
        guard !values.isEmpty else { return nil }
        return Double(values.filter(\.self).count) / Double(values.count)
    }

    var averageHoldMs: Double? {
        let holds = exercises.flatMap { $0.sets.flatMap(\.holdDurations) }
        guard !holds.isEmpty else { return nil }
        return Double(holds.reduce(0, +)) / Double(holds.count)
    }
}

extension IMURecording {
    var observedSampleRate: Double? {
        guard let duration, duration > 0 else { return nil }
        return Double(sampleCount) / duration
    }
}
