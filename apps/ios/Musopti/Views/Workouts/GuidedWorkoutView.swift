import SwiftUI

struct GuidedWorkoutView: View {
    @Environment(AppRouter.self) private var router
    @Environment(ExerciseCatalog.self) private var exerciseCatalog
    @Environment(SessionManager.self) private var sessionManager
    @Environment(BLEManager.self) private var bleManager
    @Environment(\.dismiss) private var dismiss

    let template: WorkoutTemplate

    @State private var currentExerciseIndex: Int = 0

    private var entries: [WorkoutTemplateEntry] {
        template.exercises.sorted(by: { $0.order < $1.order })
    }

    private var currentEntry: WorkoutTemplateEntry? {
        guard entries.indices.contains(currentExerciseIndex) else { return nil }
        return entries[currentExerciseIndex]
    }

    private var currentExercise: Exercise? {
        guard let entry = currentEntry else { return nil }
        return exerciseCatalog.exercise(id: entry.exerciseID)
    }

    private var nextEntry: WorkoutTemplateEntry? {
        guard entries.indices.contains(currentExerciseIndex + 1) else { return nil }
        return entries[currentExerciseIndex + 1]
    }

    private var nextExercise: Exercise? {
        guard let entry = nextEntry else { return nil }
        return exerciseCatalog.exercise(id: entry.exerciseID)
    }

    private var setsCompleted: Int {
        guard let entry = currentEntry,
              let session = sessionManager.activeSession,
              let log = session.exercises.first(where: { $0.exerciseID == entry.exerciseID })
        else { return 0 }
        return log.sets.count
    }

    private var progress: Double {
        guard !entries.isEmpty else { return 0 }
        return Double(currentExerciseIndex + 1) / Double(entries.count)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: MusoptiTheme.largePadding) {
                progressHeader
                exerciseContent
                actionButtons
            }
            .padding(MusoptiTheme.largePadding)
        }
        .background(MusoptiTheme.surfaceBackground)
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            syncCurrentIndexToSession()
            if sessionManager.currentExercise == nil {
                activateCurrentExercise()
            }
        }
        .onChange(of: sessionManager.currentExercise?.id) { _, _ in
            syncCurrentIndexToSession()
        }
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: MusoptiTheme.smallPadding) {
            ProgressView(value: progress)
                .tint(MusoptiTheme.accent)

            HStack {
                Text("Exercise \(min(currentExerciseIndex + 1, entries.count)) of \(entries.count)")
                    .font(MusoptiTheme.caption.weight(.semibold))
                    .foregroundStyle(MusoptiTheme.textSecondary)
                Spacer()
                if let nextExercise {
                    HStack(spacing: 6) {
                        ExerciseIconView(exercise: nextExercise, size: 28)
                        Text("Next: \(nextExercise.name)")
                            .font(MusoptiTheme.caption)
                            .foregroundStyle(MusoptiTheme.textTertiary)
                    }
                }
            }
        }
        .padding(MusoptiTheme.mediumPadding)
        .background(MusoptiTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius))
    }

    private var exerciseContent: some View {
        VStack(alignment: .leading, spacing: MusoptiTheme.mediumPadding) {
            if let entry = currentEntry {
                HStack(alignment: .top, spacing: 12) {
                    if let currentExercise {
                        ExerciseIconView(exercise: currentExercise, size: 54)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.exerciseName)
                            .font(MusoptiTheme.sectionTitle)
                            .foregroundStyle(MusoptiTheme.textPrimary)

                        if let currentExercise {
                            Text("\(currentExercise.category.displayName) • \(currentExercise.equipmentDisplayName)")
                                .font(MusoptiTheme.caption)
                                .foregroundStyle(MusoptiTheme.textSecondary)
                        }
                    }
                }

                Text("\(entry.targetSets) sets x \(entry.targetReps) reps")
                    .font(MusoptiTheme.timer)
                    .foregroundStyle(MusoptiTheme.accent)

                HStack(spacing: MusoptiTheme.smallPadding) {
                    ForEach(0..<entry.targetSets, id: \.self) { index in
                        Circle()
                            .fill(index < setsCompleted ? MusoptiTheme.valid : MusoptiTheme.textTertiary)
                            .frame(width: 12, height: 12)
                    }
                }

                Text("\(setsCompleted) / \(entry.targetSets) sets completed")
                    .font(MusoptiTheme.bodyText)
                    .foregroundStyle(MusoptiTheme.textSecondary)

                if let nextExercise {
                    HStack(spacing: 8) {
                        ExerciseIconView(exercise: nextExercise, size: 32)
                        Text("After this: \(nextExercise.name)")
                            .font(MusoptiTheme.caption)
                            .foregroundStyle(MusoptiTheme.textTertiary)
                    }
                }
            } else {
                Text("Workout complete")
                    .font(MusoptiTheme.sectionTitle)
                    .foregroundStyle(MusoptiTheme.valid)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MusoptiTheme.largePadding)
        .background(MusoptiTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius))
    }

    private var actionButtons: some View {
        VStack(spacing: MusoptiTheme.smallPadding) {
            Button {
                router.navigateToSession()
                dismiss()
            } label: {
                Text("Open Session")
                    .font(MusoptiTheme.bodyText.weight(.semibold))
                    .foregroundStyle(MusoptiTheme.surfaceBackground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, MusoptiTheme.mediumPadding)
                    .background(MusoptiTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius))
            }
            .buttonStyle(.plain)

            HStack(spacing: MusoptiTheme.smallPadding) {
                Button {
                    advanceToNextExercise()
                } label: {
                    Text("Skip")
                        .font(MusoptiTheme.bodyText.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MusoptiTheme.mediumPadding)
                        .background(MusoptiTheme.surfaceBackground)
                        .clipShape(RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius))
                }
                .buttonStyle(.plain)

                Button {
                    advanceToNextExercise()
                } label: {
                    Text(isLastExercise ? "Mark Complete" : "Next Exercise")
                        .font(MusoptiTheme.bodyText.weight(.semibold))
                        .foregroundStyle(MusoptiTheme.surfaceBackground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MusoptiTheme.mediumPadding)
                        .background(MusoptiTheme.valid)
                        .clipShape(RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius))
                }
                .buttonStyle(.plain)
            }

            Button {
                sessionManager.finishSession()
                if let sessionID = sessionManager.lastCompletedSessionID {
                    router.navigateToHistory(sessionID: sessionID)
                }
                dismiss()
            } label: {
                Text("Finish Workout")
                    .font(MusoptiTheme.bodyText.weight(.semibold))
                    .foregroundStyle(MusoptiTheme.warning)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, MusoptiTheme.mediumPadding)
                    .overlay(
                        RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius)
                            .stroke(MusoptiTheme.warning, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var isLastExercise: Bool {
        currentExerciseIndex >= entries.count - 1
    }

    private func syncCurrentIndexToSession() {
        guard let currentID = sessionManager.currentExercise?.id,
              let index = entries.firstIndex(where: { $0.exerciseID == currentID })
        else {
            return
        }
        currentExerciseIndex = index
    }

    private func advanceToNextExercise() {
        if isLastExercise {
            router.navigateToSession()
            dismiss()
            return
        }

        currentExerciseIndex += 1
        activateCurrentExercise()
    }

    private func activateCurrentExercise() {
        guard let entry = currentEntry,
              let exercise = exerciseCatalog.exercise(id: entry.exerciseID)
        else {
            return
        }

        sessionManager.selectExercise(exercise)

        let profile = exercise.detectionProfile
        let config = MusoptiConfig(
            deviceMode: .detection,
            exerciseType: MusoptiExerciseType(rawValue: profile.firmwareExerciseType) ?? .generic,
            holdTargetMs: profile.holdTargetMs,
            holdToleranceMs: profile.holdToleranceMs,
            minRepDurationMs: profile.minRepDurationMs,
            sampleRateHz: 100
        )
        bleManager.writeConfig(config, verifyReadBack: true)
    }
}
