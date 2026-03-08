import Foundation
import Observation
import SwiftData

enum DateRange: String, CaseIterable, Identifiable {
    case oneWeek = "1W"
    case oneMonth = "1M"
    case threeMonths = "3M"
    case sixMonths = "6M"
    case oneYear = "1Y"
    case all = "All"

    var id: String { rawValue }

    var startDate: Date {
        let calendar = Calendar.current
        let now = Date.now
        switch self {
        case .oneWeek:    return calendar.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
        case .oneMonth:   return calendar.date(byAdding: .month, value: -1, to: now) ?? now
        case .threeMonths: return calendar.date(byAdding: .month, value: -3, to: now) ?? now
        case .sixMonths:  return calendar.date(byAdding: .month, value: -6, to: now) ?? now
        case .oneYear:    return calendar.date(byAdding: .year, value: -1, to: now) ?? now
        case .all:        return .distantPast
        }
    }
}

@Observable
final class StatsEngine {
    private var modelContext: ModelContext?

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func weeklyVolume(for range: DateRange) -> [(week: Date, volume: Double)] {
        let sessions = fetchSessions(from: range.startDate)
        let calendar = Calendar.current

        var volumeByWeek: [Date: Double] = [:]
        for session in sessions {
            let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: session.startedAt)) ?? session.startedAt
            volumeByWeek[weekStart, default: 0] += session.totalVolume
        }

        return volumeByWeek
            .map { (week: $0.key, volume: $0.value) }
            .sorted { $0.week < $1.week }
    }

    func workoutsPerWeek(for range: DateRange) -> [(week: Date, count: Int)] {
        let sessions = fetchSessions(from: range.startDate)
        let calendar = Calendar.current

        var countByWeek: [Date: Int] = [:]
        for session in sessions {
            let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: session.startedAt)) ?? session.startedAt
            countByWeek[weekStart, default: 0] += 1
        }

        return countByWeek
            .map { (week: $0.key, count: $0.value) }
            .sorted { $0.week < $1.week }
    }

    func holdConsistency(for range: DateRange) -> [(week: Date, successRate: Double)] {
        let sessions = fetchSessions(from: range.startDate)
        let calendar = Calendar.current

        var buckets: [Date: (valid: Int, total: Int)] = [:]

        for session in sessions {
            let weekStart = calendar.date(
                from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: session.startedAt)
            ) ?? session.startedAt

            let values = session.exercises.flatMap { $0.sets.flatMap(\.holdValids) }
            guard !values.isEmpty else { continue }

            buckets[weekStart, default: (0, 0)].valid += values.filter(\.self).count
            buckets[weekStart, default: (0, 0)].total += values.count
        }

        return buckets
            .compactMap { week, value in
                guard value.total > 0 else { return nil }
                return (week: week, successRate: Double(value.valid) / Double(value.total))
            }
            .sorted { $0.week < $1.week }
    }

    func exerciseProgression(exerciseID: UUID, range: DateRange) -> [(date: Date, maxVolume: Double)] {
        let sessions = fetchSessions(from: range.startDate)

        var results: [(date: Date, maxVolume: Double)] = []
        for session in sessions {
            for log in session.exercises where log.exerciseID == exerciseID {
                let maxSetVolume = log.sets.map { Double($0.reps) * ($0.weightKg ?? 0) }.max() ?? 0
                if maxSetVolume > 0 {
                    results.append((date: session.startedAt, maxVolume: maxSetVolume))
                }
            }
        }

        return results.sorted { $0.date < $1.date }
    }

    func sessionsForExercise(_ exerciseID: UUID) -> [WorkoutSession] {
        let all = fetchSessions(from: .distantPast)
        return all.filter { session in
            session.exercises.contains { $0.exerciseID == exerciseID }
        }
    }

    func sessions(for range: DateRange) -> [WorkoutSession] {
        fetchSessions(from: range.startDate)
    }

    func totalVolume(for range: DateRange) -> Double {
        sessions(for: range).reduce(0) { $0 + $1.totalVolume }
    }

    // MARK: - Private

    private func fetchSessions(from startDate: Date) -> [WorkoutSession] {
        guard let context = modelContext else { return [] }
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.startedAt >= startDate && $0.finishedAt != nil },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}
