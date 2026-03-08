import SwiftUI

struct SessionDetailView: View {
    @Environment(AppPreferences.self) private var preferences

    let session: WorkoutSession

    private var formattedDate: String {
        session.startedAt.formatted(date: .long, time: .shortened)
    }

    private var formattedDuration: String {
        guard let duration = session.duration else { return "—" }
        return duration.formatted
    }

    var body: some View {
        ScrollView {
            VStack(spacing: MusoptiTheme.largePadding) {
                headerSection
                summarySection
                exercisesSection
            }
            .padding(MusoptiTheme.mediumPadding)
        }
        .background(MusoptiTheme.surfaceBackground)
        .navigationTitle(session.templateName ?? "Freeform")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerSection: some View {
        VStack(spacing: 4) {
            Text(session.templateName ?? "Freeform Session")
                .font(MusoptiTheme.sectionTitle)
                .foregroundStyle(MusoptiTheme.textPrimary)
            Text(formattedDate)
                .font(MusoptiTheme.bodyText)
                .foregroundStyle(MusoptiTheme.textSecondary)
            Text(formattedDuration)
                .font(MusoptiTheme.timer)
                .foregroundStyle(MusoptiTheme.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(MusoptiTheme.largePadding)
        .background(MusoptiTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius))
    }

    private var summarySection: some View {
        HStack {
            SummaryStatView(title: "Sets", value: "\(session.totalSets)", icon: "repeat")
            Spacer()
            SummaryStatView(title: "Reps", value: "\(session.totalReps)", icon: "number")
            Spacer()
            SummaryStatView(
                title: "Volume",
                value: session.totalVolume.formattedWeight(unit: preferences.weightUnit),
                icon: "scalemass"
            )
            Spacer()
            SummaryStatView(
                title: "Hold",
                value: session.holdSuccessRate.map { "\(Int($0 * 100))%" } ?? "—",
                icon: "target"
            )
        }
        .padding(MusoptiTheme.mediumPadding)
        .background(MusoptiTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius))
    }

    private var exercisesSection: some View {
        VStack(alignment: .leading, spacing: MusoptiTheme.mediumPadding) {
            ForEach(session.exercises.sorted(by: { $0.order < $1.order })) { log in
                ExerciseLogCard(log: log, weightUnit: preferences.weightUnit)
            }
        }
    }
}

private struct SummaryStatView: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(MusoptiTheme.accent)
            Text(value)
                .font(MusoptiTheme.bodyText.weight(.bold))
                .foregroundStyle(MusoptiTheme.textPrimary)
                .multilineTextAlignment(.center)
            Text(title)
                .font(MusoptiTheme.caption)
                .foregroundStyle(MusoptiTheme.textSecondary)
        }
    }
}

private struct ExerciseLogCard: View {
    @Environment(ExerciseCatalog.self) private var exerciseCatalog
    let log: ExerciseLog
    let weightUnit: WeightUnit

    private var resolvedExercise: Exercise? {
        exerciseCatalog.exercise(id: log.exerciseID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MusoptiTheme.mediumPadding) {
            HStack(spacing: 10) {
                if let resolvedExercise {
                    ExerciseIconView(exercise: resolvedExercise, size: 42)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(log.exerciseName)
                        .font(MusoptiTheme.bodyText.weight(.semibold))
                        .foregroundStyle(MusoptiTheme.textPrimary)

                    if let resolvedExercise {
                        Text("\(resolvedExercise.category.displayName) • \(resolvedExercise.equipmentDisplayName)")
                            .font(MusoptiTheme.caption)
                            .foregroundStyle(MusoptiTheme.textSecondary)
                    }
                }
            }

            HStack(spacing: MusoptiTheme.mediumPadding) {
                exerciseStat(title: "Sets", value: "\(log.sets.count)")
                exerciseStat(title: "Reps", value: "\(log.totalReps)")
                exerciseStat(title: "Volume", value: log.totalVolume.formattedWeight(unit: weightUnit))
                exerciseStat(
                    title: "Hold",
                    value: log.holdSuccessRate.map { "\(Int($0 * 100))%" } ?? "—"
                )
            }

            setHeaderRow

            ForEach(log.sets) { set in
                SetRowView(set: set, weightUnit: weightUnit)
            }
        }
        .padding(MusoptiTheme.mediumPadding)
        .background(MusoptiTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius))
    }

    private func exerciseStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(MusoptiTheme.bodyText.weight(.bold))
                .foregroundStyle(MusoptiTheme.textPrimary)
            Text(title)
                .font(MusoptiTheme.caption)
                .foregroundStyle(MusoptiTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var setHeaderRow: some View {
        HStack {
            Text("Set")
                .frame(width: 36, alignment: .leading)
            Text("Reps")
                .frame(width: 44, alignment: .center)
            Text("Weight")
                .frame(width: 72, alignment: .center)
            Text("Avg Hold")
                .frame(width: 72, alignment: .center)
            Text("Valid")
                .frame(width: 52, alignment: .center)
            Spacer()
        }
        .font(MusoptiTheme.caption.weight(.semibold))
        .foregroundStyle(MusoptiTheme.textTertiary)
    }
}

private struct SetRowView: View {
    let set: SetLog
    let weightUnit: WeightUnit
    @State private var isExpanded = false

    private var avgHold: String {
        guard let averageHoldMs = set.averageHoldMs else { return "—" }
        return String(format: "%.0fms", averageHoldMs)
    }

    private var weightText: String {
        guard let weightKg = set.weightKg, weightKg > 0 else { return "—" }
        return weightKg.formattedWeight(unit: weightUnit)
    }

    private var validText: String {
        guard let holdSuccessRate = set.holdSuccessRate else { return "—" }
        return "\(Int(holdSuccessRate * 100))%"
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                if !set.holdDurations.isEmpty {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
            } label: {
                HStack {
                    Text("#\(set.setNumber)")
                        .frame(width: 36, alignment: .leading)
                    Text("\(set.reps)")
                        .frame(width: 44, alignment: .center)
                    Text(weightText)
                        .frame(width: 72, alignment: .center)
                    Text(avgHold)
                        .frame(width: 72, alignment: .center)
                    Text(validText)
                        .frame(width: 52, alignment: .center)
                    Spacer()
                    if !set.holdDurations.isEmpty {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10))
                            .foregroundStyle(MusoptiTheme.textTertiary)
                    }
                }
                .font(MusoptiTheme.bodyText)
                .foregroundStyle(MusoptiTheme.textPrimary)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            if isExpanded {
                holdDetails
            }
        }
    }

    private var holdDetails: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(set.holdDurations.enumerated()), id: \.offset) { index, duration in
                HStack(spacing: MusoptiTheme.smallPadding) {
                    Text("Rep \(index + 1)")
                        .foregroundStyle(MusoptiTheme.textSecondary)

                    Text("\(duration)ms")
                        .foregroundStyle(MusoptiTheme.textPrimary)

                    if index < set.holdValids.count {
                        Image(systemName: set.holdValids[index] ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(set.holdValids[index] ? MusoptiTheme.valid : MusoptiTheme.warning)
                    }
                }
                .font(MusoptiTheme.caption)
            }
        }
        .padding(.leading, MusoptiTheme.largePadding)
        .padding(.bottom, MusoptiTheme.smallPadding)
    }
}
