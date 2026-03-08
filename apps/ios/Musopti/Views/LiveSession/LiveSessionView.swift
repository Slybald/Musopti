import SwiftUI
import SwiftData

struct LiveSessionView: View {
    @Environment(AppPreferences.self) private var preferences
    @Environment(AppRouter.self) private var router
    @Environment(SessionManager.self) private var sessionManager
    @Environment(BLEManager.self) private var bleManager
    @Environment(\.modelContext) private var modelContext
    @State private var isGraphExpanded = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: MusoptiTheme.largePadding) {
                    deviceBar
                    ExercisePickerView()
                    performanceHero
                    liveDetails
                }
                .padding(.horizontal, MusoptiTheme.mediumPadding)
                .padding(.top, MusoptiTheme.smallPadding)
                .padding(.bottom, MusoptiTheme.largePadding)
            }
            .background(MusoptiTheme.surfaceBackground)
            .navigationTitle("Session")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    sessionButton
                }
            }
        }
        .onAppear {
            sessionManager.configure(modelContext: modelContext)
            isGraphExpanded = preferences.showGraphByDefault
        }
    }

    @ViewBuilder
    private var sessionButton: some View {
        if sessionManager.isSessionActive {
            Button("Finish") {
                sessionManager.finishSession()
                if let sessionID = sessionManager.lastCompletedSessionID {
                    router.navigateToHistory(sessionID: sessionID)
                }
            }
            .foregroundStyle(MusoptiTheme.warning)
        } else {
            Button("Start") {
                sessionManager.startSession()
            }
            .foregroundStyle(MusoptiTheme.accent)
        }
    }

    private var deviceBar: some View {
        HStack(spacing: MusoptiTheme.mediumPadding) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Device")
                    .font(MusoptiTheme.caption.weight(.semibold))
                    .foregroundStyle(MusoptiTheme.textSecondary)

                HStack(spacing: 8) {
                    Circle()
                        .fill(connectionColor)
                        .frame(width: 10, height: 10)
                    Text(bleManager.deviceStatus.connectionState.title)
                        .font(MusoptiTheme.bodyText.weight(.semibold))
                        .foregroundStyle(MusoptiTheme.textPrimary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(bleManager.isConfigInSync ? "Config synced" : "Config not synced")
                    .font(MusoptiTheme.caption.weight(.semibold))
                    .foregroundStyle(bleManager.isConfigInSync ? MusoptiTheme.valid : MusoptiTheme.warning)

                Text(bleManager.deviceStatus.rssi.map { "\($0) dBm" } ?? "Signal unavailable")
                    .font(MusoptiTheme.caption)
                    .foregroundStyle(MusoptiTheme.textSecondary)
            }
        }
        .padding(MusoptiTheme.mediumPadding)
        .background(MusoptiTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius))
    }

    private var performanceHero: some View {
        VStack(alignment: .leading, spacing: MusoptiTheme.mediumPadding) {
            HStack(alignment: .top) {
                if let currentExercise = sessionManager.currentExercise {
                    HStack(alignment: .top, spacing: 12) {
                        ExerciseIconView(exercise: currentExercise, size: 56)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(currentExercise.name)
                                .font(MusoptiTheme.sectionTitle)
                                .foregroundStyle(MusoptiTheme.textPrimary)
                                .lineLimit(2)

                            Text("\(currentExercise.category.displayName) • \(currentExercise.equipmentDisplayName)")
                                .font(MusoptiTheme.caption)
                                .foregroundStyle(MusoptiTheme.textSecondary)

                            Text("Set \(sessionManager.currentSetSummary?.setNumber ?? sessionManager.currentSetNumber)")
                                .font(MusoptiTheme.caption.weight(.semibold))
                                .foregroundStyle(MusoptiTheme.textSecondary)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select an exercise")
                            .font(MusoptiTheme.sectionTitle)
                            .foregroundStyle(MusoptiTheme.textPrimary)

                        Text("Set \(sessionManager.currentSetSummary?.setNumber ?? sessionManager.currentSetNumber)")
                            .font(MusoptiTheme.caption.weight(.semibold))
                            .foregroundStyle(MusoptiTheme.textSecondary)
                    }
                }

                Spacer()

                Text(sessionSummaryLine)
                    .font(MusoptiTheme.caption.weight(.semibold))
                    .foregroundStyle(MusoptiTheme.textSecondary)
                    .multilineTextAlignment(.trailing)
            }

            HStack(alignment: .bottom) {
                Text("\(sessionManager.currentSetReps)")
                    .font(MusoptiTheme.repCounter)
                    .foregroundStyle(MusoptiTheme.textPrimary)
                    .contentTransition(.numericText())

                VStack(alignment: .leading, spacing: 6) {
                    Text("reps")
                        .font(MusoptiTheme.caption)
                        .foregroundStyle(MusoptiTheme.textSecondary)

                    phaseBadge
                }

                Spacer()
            }

            HStack(spacing: MusoptiTheme.smallPadding) {
                holdTargetPill
                if sessionManager.currentPhase == .hold,
                   let holdPhaseStartedAt = sessionManager.holdPhaseStartedAt {
                    holdTimer(startedAt: holdPhaseStartedAt)
                } else if sessionManager.currentExercise?.detectionProfile.requireHold == true {
                    HoldResultBadge()
                }
            }

            if let lastFeedback = sessionManager.lastFeedback {
                VStack(alignment: .leading, spacing: 4) {
                    Text(lastFeedback.title)
                        .font(MusoptiTheme.bodyText.weight(.semibold))
                        .foregroundStyle(lastFeedback.isPositive ? MusoptiTheme.valid : MusoptiTheme.warning)
                    Text(lastFeedback.detail)
                        .font(MusoptiTheme.caption)
                        .foregroundStyle(MusoptiTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(MusoptiTheme.smallPadding)
                .background(MusoptiTheme.surfaceBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(MusoptiTheme.largePadding)
        .background(
            LinearGradient(
                colors: [
                    MusoptiTheme.cardBackground,
                    MusoptiTheme.accent.opacity(0.16),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var liveDetails: some View {
        VStack(spacing: MusoptiTheme.mediumPadding) {
            WeightInputView()

            if sessionManager.isResting {
                RestTimerView()
            }

            graphSection

            if let summary = sessionManager.currentSetSummary {
                currentSetStats(summary)
            }
        }
    }

    private var graphSection: some View {
        VStack(alignment: .leading, spacing: MusoptiTheme.smallPadding) {
            HStack {
                Text("Live motion")
                    .font(MusoptiTheme.bodyText.weight(.semibold))
                    .foregroundStyle(MusoptiTheme.textPrimary)
                Spacer()
                Button(isGraphExpanded ? "Hide" : "Show") {
                    isGraphExpanded.toggle()
                    preferences.showGraphByDefault = isGraphExpanded
                }
                .font(MusoptiTheme.caption.weight(.semibold))
                .foregroundStyle(MusoptiTheme.accent)
            }

            if isGraphExpanded {
                LiveAccelChart()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(MusoptiTheme.mediumPadding)
        .background(MusoptiTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius))
    }

    private func currentSetStats(_ summary: CurrentSetSummary) -> some View {
        HStack(spacing: MusoptiTheme.mediumPadding) {
            statTile(title: "Set", value: "#\(summary.setNumber)")
            statTile(title: "Reps", value: "\(summary.reps)")
            statTile(
                title: "Weight",
                value: summary.weightKg.map { $0.formattedWeight(unit: preferences.weightUnit) } ?? "--"
            )
            statTile(
                title: "Hold",
                value: summary.averageHoldMs.map { String(format: "%.0f ms", $0) } ?? "--"
            )
        }
        .padding(MusoptiTheme.mediumPadding)
        .background(MusoptiTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius))
    }

    private func statTile(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(MusoptiTheme.bodyText.weight(.bold))
                .foregroundStyle(MusoptiTheme.textPrimary)
            Text(title)
                .font(MusoptiTheme.caption)
                .foregroundStyle(MusoptiTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var phaseBadge: some View {
        Text(sessionManager.currentPhase.label)
            .font(MusoptiTheme.caption.weight(.semibold))
            .foregroundStyle(MusoptiTheme.phaseColor(for: sessionManager.currentPhase))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(MusoptiTheme.surfaceBackground)
            .clipShape(Capsule())
    }

    private var holdTargetPill: some View {
        Text(sessionManager.holdTargetDisplay)
            .font(MusoptiTheme.caption.weight(.semibold))
            .foregroundStyle(MusoptiTheme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(MusoptiTheme.surfaceBackground)
            .clipShape(Capsule())
    }

    private func holdTimer(startedAt: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let elapsed = max(context.date.timeIntervalSince(startedAt), 0)
            Text(String(format: "Hold %.1fs", elapsed))
                .font(MusoptiTheme.caption.weight(.semibold))
                .foregroundStyle(MusoptiTheme.hold)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(MusoptiTheme.surfaceBackground)
                .clipShape(Capsule())
        }
    }

    private var sessionSummaryLine: String {
        let setNumber = sessionManager.currentSetSummary?.setNumber ?? sessionManager.currentSetNumber
        let reps = sessionManager.currentSetSummary?.reps ?? sessionManager.currentSetReps
        let weight = sessionManager.currentSetSummary?.weightKg.map {
            $0.formattedWeight(unit: preferences.weightUnit)
        } ?? "No weight"

        return "Set \(setNumber) • \(reps) reps • \(weight)"
    }

    private var connectionColor: Color {
        switch bleManager.connectionState {
        case .ready:
            return MusoptiTheme.valid
        case .searching, .connecting, .recovering:
            return MusoptiTheme.warning
        case .error:
            return MusoptiTheme.invalid
        case .offline:
            return MusoptiTheme.textTertiary
        }
    }
}
