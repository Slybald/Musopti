import Foundation
import SwiftData
import Observation

@Observable
final class ExerciseCatalog {
    private var modelContext: ModelContext?

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func seedIfNeeded() {
        guard let context = modelContext else { return }

        guard let url = Bundle.main.url(forResource: "exercises", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return }

        let decoder = JSONDecoder()
        guard let entries = try? decoder.decode([ExerciseJSON].self, from: data) else { return }

        let descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.isBuiltIn })
        let builtInExercises = (try? context.fetch(descriptor)) ?? []
        var builtInsByID = Dictionary(uniqueKeysWithValues: builtInExercises.map { ($0.id, $0) })
        var didChange = false

        for entry in entries {
            guard let id = UUID(uuidString: entry.id) else { continue }

            let detectionProfile = DetectionProfile(
                firmwareExerciseType: entry.detectionProfile.firmwareExerciseType,
                requireHold: entry.detectionProfile.requireHold,
                holdTargetMs: entry.detectionProfile.holdTargetMs,
                holdToleranceMs: entry.detectionProfile.holdToleranceMs,
                minRepDurationMs: entry.detectionProfile.minRepDurationMs
            )
            let category = ExerciseCategory(rawValue: entry.category) ?? .custom

            if let existing = builtInsByID[id] {
                if existing.name != entry.name {
                    existing.name = entry.name
                    didChange = true
                }
                if existing.category != category {
                    existing.category = category
                    didChange = true
                }
                if existing.muscleGroup != entry.muscleGroup {
                    existing.muscleGroup = entry.muscleGroup
                    didChange = true
                }
                if existing.equipmentType != entry.equipmentType {
                    existing.equipmentType = entry.equipmentType
                    didChange = true
                }
                if existing.iconName != entry.iconName {
                    existing.iconName = entry.iconName
                    didChange = true
                }
                if existing.detectionProfile != detectionProfile {
                    existing.detectionProfile = detectionProfile
                    didChange = true
                }
                if !existing.isBuiltIn {
                    existing.isBuiltIn = true
                    didChange = true
                }
            } else {
                let exercise = Exercise(
                    id: id,
                    name: entry.name,
                    category: category,
                    muscleGroup: entry.muscleGroup,
                    equipmentType: entry.equipmentType,
                    isBuiltIn: true,
                    iconName: entry.iconName,
                    detectionProfile: detectionProfile
                )
                context.insert(exercise)
                builtInsByID[id] = exercise
                didChange = true
            }
        }

        if didChange {
            try? context.save()
        }
    }

    func exercises(for category: ExerciseCategory) -> [Exercise] {
        guard let context = modelContext else { return [] }
        // SwiftData #Predicate does not reliably support enum comparisons,
        // so we fetch all and filter in memory.
        let descriptor = FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.name)])
        let all = (try? context.fetch(descriptor)) ?? []
        return all.filter { $0.category == category }
    }

    func allExercises() -> [Exercise] {
        guard let context = modelContext else { return [] }
        let descriptor = FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.name)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func exercise(id: UUID) -> Exercise? {
        guard let context = modelContext else { return nil }
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate<Exercise> { $0.id == id }
        )
        return try? context.fetch(descriptor).first
    }

    func search(query: String) -> [Exercise] {
        guard let context = modelContext else { return [] }
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate<Exercise> { $0.name.localizedStandardContains(query) },
            sortBy: [SortDescriptor(\.name)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}

// MARK: - JSON Decoding Helpers

private struct ExerciseJSON: Codable {
    let id: String
    let name: String
    let category: String
    let muscleGroup: String
    let equipmentType: String
    let iconName: String
    let detectionProfile: DetectionProfileJSON
}

private struct DetectionProfileJSON: Codable {
    let firmwareExerciseType: UInt8
    let requireHold: Bool
    let holdTargetMs: UInt16
    let holdToleranceMs: UInt16
    let minRepDurationMs: UInt16
}
