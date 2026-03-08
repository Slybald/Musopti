import SwiftUI
import SwiftData

private enum HistoryPane: String, CaseIterable, Identifiable {
    case sessions = "Sessions"
    case stats = "Stats"

    var id: String { rawValue }
}

struct HistoryView: View {
    @Environment(AppPreferences.self) private var preferences
    @Environment(AppRouter.self) private var router

    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    @State private var selectedPane: HistoryPane = .sessions
    @State private var navigationPath: [UUID] = []

    private var filteredSessions: [WorkoutSession] {
        sessions.filter { session in
            let matchesRange = session.startedAt >= preferences.preferredHistoryRange.startDate
            let matchesMode: Bool = {
                switch preferences.preferredHistoryFilter {
                case .all:
                    return true
                case .freeform:
                    return session.templateID == nil
                case .template:
                    return session.templateID != nil
                }
            }()
            let matchesExercise: Bool = {
                guard let exerciseID = selectedExerciseID else { return true }
                return session.exercises.contains { $0.exerciseID == exerciseID }
            }()
            return matchesRange && matchesMode && matchesExercise
        }
    }

    private var groupedSessions: [(String, [WorkoutSession])] {
        groupByDateSection(filteredSessions)
    }

    private var selectedExerciseID: UUID? {
        UUID(uuidString: preferences.preferredHistoryExerciseID)
    }

    var body: some View {
        @Bindable var preferences = preferences

        NavigationStack(path: $navigationPath) {
            ZStack {
                MusoptiTheme.surfaceBackground.ignoresSafeArea()

                VStack(spacing: MusoptiTheme.mediumPadding) {
                    panePicker
                    filterBar(preferences: $preferences)

                    if filteredSessions.isEmpty {
                        emptyState
                    } else if selectedPane == .sessions {
                        sessionsList
                    } else {
                        StatsDashboardView(
                            selectedRange: $preferences.preferredHistoryRange,
                            selectedExerciseID: Binding(
                                get: { selectedExerciseID },
                                set: { preferences.preferredHistoryExerciseID = $0?.uuidString ?? "" }
                            )
                        )
                    }
                }
                .padding(.horizontal, MusoptiTheme.mediumPadding)
                .padding(.top, MusoptiTheme.smallPadding)
            }
            .navigationTitle("History")
            .navigationDestination(for: UUID.self) { sessionID in
                if let session = sessions.first(where: { $0.id == sessionID }) {
                    SessionDetailView(session: session)
                }
            }
        }
        .onChange(of: router.highlightedSessionID) { _, sessionID in
            guard let sessionID else { return }
            navigationPath = [sessionID]
            router.highlightedSessionID = nil
        }
    }

    private var panePicker: some View {
        Picker("View", selection: $selectedPane) {
            ForEach(HistoryPane.allCases) { pane in
                Text(pane.rawValue).tag(pane)
            }
        }
        .pickerStyle(.segmented)
    }

    private func filterBar(preferences: Bindable<AppPreferences>) -> some View {
        VStack(spacing: MusoptiTheme.smallPadding) {
            HStack(spacing: MusoptiTheme.smallPadding) {
                Picker("Range", selection: preferences.preferredHistoryRange) {
                    ForEach(DateRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                Menu {
                    Button("All Exercises") {
                        preferences.preferredHistoryExerciseID.wrappedValue = ""
                    }
                    ForEach(exercises) { exercise in
                        Button(exercise.name) {
                            preferences.preferredHistoryExerciseID.wrappedValue = exercise.id.uuidString
                        }
                    }
                } label: {
                    filterChip(
                        title: selectedExerciseLabel,
                        systemImage: "figure.strengthtraining.traditional"
                    )
                }
            }

            Picker("Mode", selection: preferences.preferredHistoryFilter) {
                ForEach(HistorySessionFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var selectedExerciseLabel: String {
        guard let selectedExerciseID,
              let exercise = exercises.first(where: { $0.id == selectedExerciseID })
        else {
            return "All Exercises"
        }
        return exercise.name
    }

    private func filterChip(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(MusoptiTheme.caption.weight(.semibold))
            .foregroundStyle(MusoptiTheme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(MusoptiTheme.cardBackground)
            .clipShape(Capsule())
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: MusoptiTheme.smallPadding) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(MusoptiTheme.textTertiary)
            Text(sessions.isEmpty ? "No workouts yet" : "No sessions for these filters")
                .font(MusoptiTheme.sectionTitle)
                .foregroundStyle(MusoptiTheme.textSecondary)
            Text(sessions.isEmpty ? "Your completed sessions will appear here." : "Try a wider date range or another exercise.")
                .font(MusoptiTheme.caption)
                .foregroundStyle(MusoptiTheme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sessions List

    private var sessionsList: some View {
        ScrollView {
            LazyVStack(spacing: MusoptiTheme.largePadding, pinnedViews: .sectionHeaders) {
                ForEach(groupedSessions, id: \.0) { sectionTitle, sectionSessions in
                    Section {
                        ForEach(sectionSessions) { session in
                            NavigationLink(value: session.id) {
                                SessionCardView(session: session)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        sectionHeader(sectionTitle)
                    }
                }
            }
            .padding(.top, MusoptiTheme.smallPadding)
            .padding(.bottom, MusoptiTheme.largePadding)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(MusoptiTheme.caption.weight(.semibold))
                .foregroundStyle(MusoptiTheme.textSecondary)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.vertical, MusoptiTheme.smallPadding)
        .background(MusoptiTheme.surfaceBackground)
    }

    // MARK: - Grouping

    private func groupByDateSection(_ sessions: [WorkoutSession]) -> [(String, [WorkoutSession])] {
        let calendar = Calendar.current
        let now = Date.now
        let startOfToday = calendar.startOfDay(for: now)
        let startOfWeek = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        ) ?? startOfToday

        var today: [WorkoutSession] = []
        var thisWeek: [WorkoutSession] = []
        var earlier: [WorkoutSession] = []

        for session in sessions {
            if session.startedAt >= startOfToday {
                today.append(session)
            } else if session.startedAt >= startOfWeek {
                thisWeek.append(session)
            } else {
                earlier.append(session)
            }
        }

        var result: [(String, [WorkoutSession])] = []
        if !today.isEmpty { result.append(("Today", today)) }
        if !thisWeek.isEmpty { result.append(("This Week", thisWeek)) }
        if !earlier.isEmpty { result.append(("Earlier", earlier)) }
        return result
    }
}

private struct SessionCardView: View {
    let session: WorkoutSession

    private var formattedDate: String {
        session.startedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var formattedDuration: String {
        guard let duration = session.duration else { return "In progress" }
        return duration.formatted
    }

    private var holdSuccessText: String {
        guard let rate = session.holdSuccessRate else { return "No hold data" }
        return "\(Int(rate * 100))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MusoptiTheme.smallPadding) {
            HStack {
                Text(session.templateName ?? "Freeform")
                    .font(MusoptiTheme.bodyText.weight(.semibold))
                    .foregroundStyle(MusoptiTheme.textPrimary)
                Spacer()
                Text(formattedDate)
                    .font(MusoptiTheme.caption)
                    .foregroundStyle(MusoptiTheme.textTertiary)
            }

            HStack(spacing: MusoptiTheme.mediumPadding) {
                historyStat(icon: "figure.strengthtraining.traditional", value: "\(session.exercises.count)", label: "ex")
                historyStat(icon: "repeat", value: "\(session.totalSets)", label: "sets")
                historyStat(icon: "number", value: "\(session.totalReps)", label: "reps")
                historyStat(icon: "clock", value: formattedDuration, label: "time")
            }

            HStack(spacing: MusoptiTheme.mediumPadding) {
                Text("Volume \(String(format: "%.0f", session.totalVolume)) kg")
                Text("Hold success \(holdSuccessText)")
            }
            .font(MusoptiTheme.caption)
            .foregroundStyle(MusoptiTheme.textSecondary)
        }
        .padding(MusoptiTheme.mediumPadding)
        .background(MusoptiTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius))
    }

    private func historyStat(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(MusoptiTheme.accent)
            Text(value)
                .font(MusoptiTheme.caption.weight(.bold))
                .foregroundStyle(MusoptiTheme.textPrimary)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(MusoptiTheme.textTertiary)
        }
    }
}
