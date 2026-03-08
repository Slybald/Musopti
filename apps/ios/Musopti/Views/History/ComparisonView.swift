import SwiftUI
import SwiftData

struct ComparisonView: View {
    @Environment(StatsEngine.self) private var statsEngine
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    @State private var selectedExercise: Exercise?
    @State private var sessionA: WorkoutSession?
    @State private var sessionB: WorkoutSession?

    private var availableSessions: [WorkoutSession] {
        guard let exercise = selectedExercise else { return [] }
        return statsEngine.sessionsForExercise(exercise.id)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: MusoptiTheme.largePadding) {
                exercisePicker
                sessionPickers
                comparisonTable
            }
            .padding(MusoptiTheme.mediumPadding)
        }
        .background(MusoptiTheme.surfaceBackground)
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedExercise) {
            sessionA = nil
            sessionB = nil
        }
    }

    // MARK: - Exercise Picker

    private var exercisePicker: some View {
        VStack(alignment: .leading, spacing: MusoptiTheme.smallPadding) {
            Text("Exercise")
                .font(MusoptiTheme.caption.weight(.semibold))
                .foregroundStyle(MusoptiTheme.textSecondary)

            Menu {
                ForEach(exercises) { exercise in
                    Button(exercise.name) {
                        selectedExercise = exercise
                    }
                }
            } label: {
                HStack {
                    Text(selectedExercise?.name ?? "Select exercise")
                        .font(MusoptiTheme.bodyText)
                        .foregroundStyle(selectedExercise != nil ? MusoptiTheme.textPrimary : MusoptiTheme.textTertiary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .foregroundStyle(MusoptiTheme.textSecondary)
                }
                .padding(MusoptiTheme.mediumPadding)
                .background(MusoptiTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius))
            }
        }
    }

    // MARK: - Session Pickers

    private var sessionPickers: some View {
        HStack(spacing: MusoptiTheme.smallPadding) {
            sessionPicker(title: "Session A", selection: $sessionA, excluding: sessionB)
            sessionPicker(title: "Session B", selection: $sessionB, excluding: sessionA)
        }
    }

    private func sessionPicker(title: String, selection: Binding<WorkoutSession?>, excluding other: WorkoutSession?) -> some View {
        VStack(alignment: .leading, spacing: MusoptiTheme.smallPadding) {
            Text(title)
                .font(MusoptiTheme.caption.weight(.semibold))
                .foregroundStyle(MusoptiTheme.textSecondary)

            Menu {
                ForEach(availableSessions.filter { $0.id != other?.id }) { session in
                    Button(session.startedAt.formatted(date: .abbreviated, time: .shortened)) {
                        selection.wrappedValue = session
                    }
                }
            } label: {
                Text(selection.wrappedValue?.startedAt.formatted(date: .abbreviated, time: .shortened) ?? "Select")
                    .font(MusoptiTheme.caption)
                    .foregroundStyle(selection.wrappedValue != nil ? MusoptiTheme.textPrimary : MusoptiTheme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(MusoptiTheme.smallPadding)
                    .background(MusoptiTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius / 2))
            }
            .disabled(availableSessions.isEmpty)
        }
    }

    // MARK: - Comparison Table

    private var comparisonTable: some View {
        VStack(spacing: 0) {
            if let a = sessionA, let b = sessionB, let exercise = selectedExercise {
                let statsA = exerciseStats(for: exercise.id, in: a)
                let statsB = exerciseStats(for: exercise.id, in: b)

                comparisonRow("Sets", valueA: "\(statsA.sets)", valueB: "\(statsB.sets)")
                Divider().overlay(MusoptiTheme.textTertiary)
                comparisonRow("Reps", valueA: "\(statsA.reps)", valueB: "\(statsB.reps)")
                Divider().overlay(MusoptiTheme.textTertiary)
                comparisonRow("Volume", valueA: String(format: "%.0f kg", statsA.volume), valueB: String(format: "%.0f kg", statsB.volume))
                Divider().overlay(MusoptiTheme.textTertiary)
                comparisonRow("Avg Hold", valueA: formatHold(statsA.avgHold), valueB: formatHold(statsB.avgHold))
            } else {
                Text("Select an exercise and two sessions to compare")
                    .font(MusoptiTheme.caption)
                    .foregroundStyle(MusoptiTheme.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .padding(MusoptiTheme.mediumPadding)
        .background(MusoptiTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius))
    }

    private func comparisonRow(_ label: String, valueA: String, valueB: String) -> some View {
        HStack {
            Text(valueA)
                .font(MusoptiTheme.bodyText.weight(.bold))
                .foregroundStyle(MusoptiTheme.accent)
                .frame(maxWidth: .infinity)

            Text(label)
                .font(MusoptiTheme.caption)
                .foregroundStyle(MusoptiTheme.textSecondary)
                .frame(width: 64)

            Text(valueB)
                .font(MusoptiTheme.bodyText.weight(.bold))
                .foregroundStyle(MusoptiTheme.accent)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, MusoptiTheme.smallPadding)
    }

    // MARK: - Helpers

    private struct ExerciseStats {
        var sets: Int = 0
        var reps: Int = 0
        var volume: Double = 0
        var avgHold: Double? = nil
    }

    private func exerciseStats(for exerciseID: UUID, in session: WorkoutSession) -> ExerciseStats {
        guard let log = session.exercises.first(where: { $0.exerciseID == exerciseID }) else {
            return ExerciseStats()
        }

        let sets = log.sets.count
        let reps = log.sets.reduce(0) { $0 + $1.reps }
        let volume = log.sets.reduce(0.0) { $0 + Double($1.reps) * ($1.weightKg ?? 0) }

        let allHolds = log.sets.flatMap { $0.holdDurations }
        let avgHold: Double? = allHolds.isEmpty ? nil : Double(allHolds.reduce(0, +)) / Double(allHolds.count)

        return ExerciseStats(sets: sets, reps: reps, volume: volume, avgHold: avgHold)
    }

    private func formatHold(_ ms: Double?) -> String {
        guard let ms else { return "—" }
        return String(format: "%.0fms", ms)
    }
}
