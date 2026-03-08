import SwiftUI
import Charts

struct RecordingPreviewView: View {
    @Environment(ExerciseCatalog.self) private var exerciseCatalog
    let recording: IMURecording

    @State private var chartData: [AccelChartPoint] = []
    @State private var isLoading = true
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false

    private let recordingManager = RecordingManager()

    private var resolvedExercise: Exercise? {
        guard let exerciseID = recording.exerciseID else { return nil }
        return exerciseCatalog.exercise(id: exerciseID)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: MusoptiTheme.mediumPadding) {
                headerCard
                chartCard
                detailsCard
            }
            .padding()
        }
        .background(MusoptiTheme.surfaceBackground)
        .navigationTitle("Recording")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    exportCSV()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .tint(MusoptiTheme.accent)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: shareItems)
        }
        .task {
            loadChartData()
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 12) {
                    if let resolvedExercise {
                        ExerciseIconView(exercise: resolvedExercise, size: 46)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(recording.exerciseName)
                            .font(MusoptiTheme.sectionTitle)
                            .foregroundStyle(MusoptiTheme.textPrimary)

                        if let resolvedExercise {
                            Text("\(resolvedExercise.category.displayName) • \(resolvedExercise.equipmentDisplayName)")
                                .font(MusoptiTheme.caption)
                                .foregroundStyle(MusoptiTheme.textSecondary)
                        }
                    }
                }
                Spacer()
                Text(recording.startedAt.relativeFormatted)
                    .font(MusoptiTheme.caption)
                    .foregroundStyle(MusoptiTheme.textSecondary)
            }

            HStack(spacing: 16) {
                if let duration = recording.duration {
                    Label(duration.formatted, systemImage: "clock")
                }
                Label("\(recording.sampleCount) samples", systemImage: "waveform")
                Label("\(recording.sampleRateHz) Hz", systemImage: "metronome")
                Label(recording.estimatedFileSize.formattedFileSize, systemImage: "doc")
            }
            .font(MusoptiTheme.caption)
            .foregroundStyle(MusoptiTheme.textSecondary)

            if let notes = recording.notes, !notes.isEmpty {
                Text(notes)
                    .font(MusoptiTheme.bodyText)
                    .foregroundStyle(MusoptiTheme.textSecondary)
            }
        }
        .padding()
        .background(MusoptiTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius))
    }

    // MARK: - Chart Card

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Acceleration Magnitude")
                .font(MusoptiTheme.phaseLabel)
                .foregroundStyle(MusoptiTheme.textPrimary)

            if isLoading {
                ProgressView()
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
            } else if chartData.isEmpty {
                Text("No data available")
                    .font(MusoptiTheme.bodyText)
                    .foregroundStyle(MusoptiTheme.textSecondary)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
            } else {
                Chart(chartData) { point in
                    LineMark(
                        x: .value("Time (s)", point.timeSeconds),
                        y: .value("Magnitude (g)", point.magnitude)
                    )
                    .foregroundStyle(MusoptiTheme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                }
                .chartXAxisLabel("Time (s)")
                .chartYAxisLabel("g")
                .chartXAxis {
                    AxisMarks { _ in
                        AxisGridLine(stroke: .init(lineWidth: 0.5))
                            .foregroundStyle(MusoptiTheme.textTertiary)
                        AxisValueLabel()
                            .foregroundStyle(MusoptiTheme.textSecondary)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine(stroke: .init(lineWidth: 0.5))
                            .foregroundStyle(MusoptiTheme.textTertiary)
                        AxisValueLabel()
                            .foregroundStyle(MusoptiTheme.textSecondary)
                    }
                }
                .frame(height: 250)
            }
        }
        .padding()
        .background(MusoptiTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius))
    }

    // MARK: - Details Card

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Details")
                .font(MusoptiTheme.phaseLabel)
                .foregroundStyle(MusoptiTheme.textPrimary)

            DetailRow(label: "Started", value: recording.startedAt.formatted(date: .abbreviated, time: .shortened))
            if let finished = recording.finishedAt {
                DetailRow(label: "Finished", value: finished.formatted(date: .abbreviated, time: .shortened))
            }
            DetailRow(label: "Sample Rate", value: "\(recording.sampleRateHz) Hz")
            DetailRow(label: "Total Samples", value: "\(recording.sampleCount)")
            DetailRow(label: "File Size", value: recording.estimatedFileSize.formattedFileSize)
            DetailRow(label: "File", value: recording.filePath)
        }
        .padding()
        .background(MusoptiTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius))
    }

    // MARK: - Data Loading

    private func loadChartData() {
        let samples = RecordingManager.readSamples(from: recording)
        guard !samples.isEmpty else {
            isLoading = false
            return
        }

        let maxDisplayPoints = 2000
        let stride = max(1, samples.count / maxDisplayPoints)
        let baseTimestamp = samples.first?.timestampMs ?? 0

        var points: [AccelChartPoint] = []
        points.reserveCapacity(min(samples.count, maxDisplayPoints))

        for i in Swift.stride(from: 0, to: samples.count, by: stride) {
            let s = samples[i]
            let magnitude = sqrtf(s.accelX * s.accelX + s.accelY * s.accelY + s.accelZ * s.accelZ)
            let timeSeconds = Double(s.timestampMs - baseTimestamp) / 1000.0
            points.append(AccelChartPoint(timeSeconds: timeSeconds, magnitude: Double(magnitude)))
        }

        chartData = points
        isLoading = false
    }

    // MARK: - Export

    private func exportCSV() {
        if let url = recordingManager.exportToCSV(recording: recording) {
            shareItems = [url]
            showShareSheet = true
        }
    }
}

// MARK: - Chart Data Point

struct AccelChartPoint: Identifiable {
    let id = UUID()
    let timeSeconds: Double
    let magnitude: Double
}

// MARK: - Detail Row

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(MusoptiTheme.bodyText)
                .foregroundStyle(MusoptiTheme.textSecondary)
            Spacer()
            Text(value)
                .font(MusoptiTheme.bodyText)
                .foregroundStyle(MusoptiTheme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }
}
