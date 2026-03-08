import SwiftUI
import Charts
import SwiftData

struct StatsDashboardView: View {
    @Environment(StatsEngine.self) private var statsEngine
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    @Binding var selectedRange: DateRange
    @Binding var selectedExerciseID: UUID?

    private var volumeData: [(week: Date, volume: Double)] {
        statsEngine.weeklyVolume(for: selectedRange)
    }

    private var frequencyData: [(week: Date, count: Int)] {
        statsEngine.workoutsPerWeek(for: selectedRange)
    }

    private var holdConsistencyData: [(week: Date, successRate: Double)] {
        statsEngine.holdConsistency(for: selectedRange)
    }

    private var progressionData: [(date: Date, maxVolume: Double)] {
        guard let selectedExerciseID else { return [] }
        return statsEngine.exerciseProgression(exerciseID: selectedExerciseID, range: selectedRange)
    }

    private var selectedExerciseName: String {
        guard let selectedExerciseID,
              let exercise = exercises.first(where: { $0.id == selectedExerciseID })
        else {
            return "Select exercise"
        }
        return exercise.name
    }

    var body: some View {
        ScrollView {
            VStack(spacing: MusoptiTheme.largePadding) {
                summaryCards
                volumeChart
                frequencyChart
                holdConsistencyChart
                progressionChart
            }
            .padding(.bottom, MusoptiTheme.largePadding)
        }
    }

    private var summaryCards: some View {
        HStack(spacing: MusoptiTheme.smallPadding) {
            summaryCard(
                title: "Volume",
                value: String(format: "%.0f kg", statsEngine.totalVolume(for: selectedRange)),
                icon: "scalemass"
            )
            summaryCard(
                title: "Sessions",
                value: "\(statsEngine.sessions(for: selectedRange).count)",
                icon: "calendar"
            )
        }
    }

    private func summaryCard(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(MusoptiTheme.accent)
            Text(value)
                .font(MusoptiTheme.bodyText.weight(.bold))
                .foregroundStyle(MusoptiTheme.textPrimary)
            Text(title)
                .font(MusoptiTheme.caption)
                .foregroundStyle(MusoptiTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MusoptiTheme.mediumPadding)
        .background(MusoptiTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius))
    }

    private var volumeChart: some View {
        statsCard(title: "Weekly Volume (kg)") {
            if volumeData.isEmpty {
                chartPlaceholder("No completed sessions for this period.")
            } else {
                Chart {
                    ForEach(volumeData, id: \.week) { entry in
                        BarMark(
                            x: .value("Week", entry.week, unit: .weekOfYear),
                            y: .value("Volume", entry.volume)
                        )
                        .foregroundStyle(MusoptiTheme.accent.gradient)
                        .cornerRadius(4)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(MusoptiTheme.textTertiary)
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .foregroundStyle(MusoptiTheme.textSecondary)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(MusoptiTheme.textTertiary)
                        AxisValueLabel()
                            .foregroundStyle(MusoptiTheme.textSecondary)
                    }
                }
                .frame(height: 220)
            }
        }
    }

    private var frequencyChart: some View {
        statsCard(title: "Workouts per Week") {
            if frequencyData.isEmpty {
                chartPlaceholder("No workouts found for this range.")
            } else {
                Chart {
                    ForEach(frequencyData, id: \.week) { entry in
                        BarMark(
                            x: .value("Week", entry.week, unit: .weekOfYear),
                            y: .value("Count", entry.count)
                        )
                        .foregroundStyle(MusoptiTheme.valid.gradient)
                        .cornerRadius(4)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(MusoptiTheme.textTertiary)
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .foregroundStyle(MusoptiTheme.textSecondary)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(MusoptiTheme.textTertiary)
                        AxisValueLabel()
                            .foregroundStyle(MusoptiTheme.textSecondary)
                    }
                }
                .frame(height: 220)
            }
        }
    }

    private var holdConsistencyChart: some View {
        statsCard(title: "Hold Consistency") {
            if holdConsistencyData.isEmpty {
                chartPlaceholder("No hold data captured yet.")
            } else {
                Chart {
                    ForEach(holdConsistencyData, id: \.week) { entry in
                        LineMark(
                            x: .value("Week", entry.week, unit: .weekOfYear),
                            y: .value("Success Rate", entry.successRate)
                        )
                        .foregroundStyle(MusoptiTheme.warning)
                        .interpolationMethod(.catmullRom)

                        AreaMark(
                            x: .value("Week", entry.week, unit: .weekOfYear),
                            y: .value("Success Rate", entry.successRate)
                        )
                        .foregroundStyle(MusoptiTheme.warning.opacity(0.18))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(MusoptiTheme.textTertiary)
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .foregroundStyle(MusoptiTheme.textSecondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 0.25, 0.5, 0.75, 1]) { value in
                        AxisGridLine()
                            .foregroundStyle(MusoptiTheme.textTertiary)
                        AxisValueLabel {
                            if let rate = value.as(Double.self) {
                                Text("\(Int(rate * 100))%")
                            }
                        }
                        .foregroundStyle(MusoptiTheme.textSecondary)
                    }
                }
                .frame(height: 220)
            }
        }
    }

    private var progressionChart: some View {
        statsCard(title: "Exercise Progression") {
            Menu {
                Button("Clear exercise") {
                    selectedExerciseID = nil
                }
                ForEach(exercises) { exercise in
                    Button(exercise.name) {
                        selectedExerciseID = exercise.id
                    }
                }
            } label: {
                HStack {
                    Text(selectedExerciseName)
                    Spacer()
                    Image(systemName: "chevron.down")
                }
                .font(MusoptiTheme.caption.weight(.semibold))
                .foregroundStyle(MusoptiTheme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(MusoptiTheme.surfaceBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if selectedExerciseID == nil {
                chartPlaceholder("Select an exercise to see its progression.")
            } else if progressionData.isEmpty {
                chartPlaceholder("No progression data available for this exercise.")
            } else {
                Chart {
                    ForEach(progressionData, id: \.date) { entry in
                        LineMark(
                            x: .value("Date", entry.date),
                            y: .value("Max Set Volume", entry.maxVolume)
                        )
                        .foregroundStyle(MusoptiTheme.accent)
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Date", entry.date),
                            y: .value("Max Set Volume", entry.maxVolume)
                        )
                        .foregroundStyle(MusoptiTheme.accent)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisGridLine()
                            .foregroundStyle(MusoptiTheme.textTertiary)
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .foregroundStyle(MusoptiTheme.textSecondary)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(MusoptiTheme.textTertiary)
                        AxisValueLabel()
                            .foregroundStyle(MusoptiTheme.textSecondary)
                    }
                }
                .frame(height: 220)
            }
        }
    }

    private func statsCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: MusoptiTheme.smallPadding) {
            Text(title)
                .font(MusoptiTheme.bodyText.weight(.semibold))
                .foregroundStyle(MusoptiTheme.textPrimary)
            content()
        }
        .padding(MusoptiTheme.mediumPadding)
        .background(MusoptiTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius))
    }

    private func chartPlaceholder(_ message: String) -> some View {
        Text(message)
            .font(MusoptiTheme.caption)
            .foregroundStyle(MusoptiTheme.textTertiary)
            .frame(maxWidth: .infinity, minHeight: 140)
    }
}
