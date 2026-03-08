import Charts
import SwiftUI
import SwiftData

struct RecordingLiveView: View {
    @Environment(AppPreferences.self) private var preferences
    @Environment(BLEManager.self) private var bleManager
    @Environment(RecordingManager.self) private var recordingManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<Exercise> { _ in true }, sort: \Exercise.name)
    private var exercises: [Exercise]

    @State private var selectedExercise: Exercise?
    @State private var sampleRateHz: Int = 100

    private let sampleRateOptions = [50, 100, 200]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: MusoptiTheme.largePadding) {
                    if !recordingManager.isRecording {
                        configSection
                    }

                    if let preflightIssue = recordingManager.preflightIssue,
                       !recordingManager.isRecording {
                        preflightCard(issue: preflightIssue)
                    }

                    liveStatsSection
                    previewSection
                    actionButton
                }
                .padding()
            }
            .background(MusoptiTheme.surfaceBackground)
            .navigationTitle(recordingManager.isRecording ? "Recording..." : "New Recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !recordingManager.isRecording {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .onAppear {
                recordingManager.configure(modelContext: modelContext)
                sampleRateHz = recordingManager.preferredSampleRateHz
                updatePreflight()
            }
            .onChange(of: sampleRateHz) { _, _ in
                updatePreflight()
            }
            .onChange(of: selectedExercise?.id) { _, _ in
                updatePreflight()
            }
            .onChange(of: bleManager.connectionState) { _, _ in
                updatePreflight()
            }
            .interactiveDismissDisabled(recordingManager.isRecording)
            .sheet(
                item: Binding(
                    get: { recordingManager.lastCompletedSummary },
                    set: { recordingManager.lastCompletedSummary = $0 }
                )
            ) { summary in
                recordingSummaryView(summary)
            }
        }
    }

    private var configSection: some View {
        VStack(spacing: MusoptiTheme.mediumPadding) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Exercise")
                    .font(MusoptiTheme.caption)
                    .foregroundStyle(MusoptiTheme.textSecondary)

                Picker("Exercise", selection: $selectedExercise) {
                    Text("Unspecified").tag(nil as Exercise?)
                    ForEach(exercises) { exercise in
                        Text(exercise.name).tag(exercise as Exercise?)
                    }
                }
                .pickerStyle(.menu)
                .tint(MusoptiTheme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(MusoptiTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Sample Rate")
                    .font(MusoptiTheme.caption)
                    .foregroundStyle(MusoptiTheme.textSecondary)

                Picker("Sample Rate", selection: $sampleRateHz) {
                    ForEach(sampleRateOptions, id: \.self) { rate in
                        Text("\(rate) Hz").tag(rate)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private func preflightCard(issue: RecordingPreflightIssue) -> some View {
        HStack(spacing: MusoptiTheme.smallPadding) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(MusoptiTheme.warning)
            Text(issue.title)
                .font(MusoptiTheme.caption)
                .foregroundStyle(MusoptiTheme.textSecondary)
            Spacer()
        }
        .padding(MusoptiTheme.mediumPadding)
        .background(MusoptiTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius))
    }

    private var liveStatsSection: some View {
        VStack(spacing: MusoptiTheme.mediumPadding) {
            if recordingManager.isRecording {
                recordingIndicator
            }

            HStack(spacing: 20) {
                StatBox(title: "Samples", value: "\(recordingManager.sampleCount)", icon: "waveform")
                StatBox(title: "Elapsed", value: TimeInterval(recordingManager.elapsedSeconds).formatted, icon: "clock")
                StatBox(title: "Rate", value: dataRateString, icon: "arrow.down.circle")
            }

            HStack {
                qualityPill
                Spacer()
                Text("Requested \(sampleRateHz) Hz")
                    .font(MusoptiTheme.caption)
                    .foregroundStyle(MusoptiTheme.textSecondary)
            }
        }
        .padding()
        .background(MusoptiTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius))
    }

    private var recordingIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .modifier(PulseModifier())
            Text("Recording in progress")
                .font(MusoptiTheme.caption)
                .foregroundStyle(MusoptiTheme.textSecondary)
        }
    }

    private var qualityPill: some View {
        Text(recordingManager.recordingQuality.title)
            .font(MusoptiTheme.caption.weight(.semibold))
            .foregroundStyle(qualityColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(MusoptiTheme.surfaceBackground)
            .clipShape(Capsule())
    }

    private var qualityColor: Color {
        switch recordingManager.recordingQuality {
        case .ok:
            return MusoptiTheme.valid
        case .noIncomingSamples, .unexpectedLowRate:
            return MusoptiTheme.warning
        }
    }

    private var dataRateString: String {
        guard recordingManager.elapsedSeconds > 0 else { return "—" }
        let samplesPerSecond = Double(recordingManager.sampleCount) / recordingManager.elapsedSeconds
        let bytesPerSecond = Int(samplesPerSecond * 28)
        return bytesPerSecond.formattedFileSize + "/s"
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: MusoptiTheme.smallPadding) {
            Text("Live Preview")
                .font(MusoptiTheme.bodyText.weight(.semibold))
                .foregroundStyle(MusoptiTheme.textPrimary)

            if recordingManager.livePreviewSamples.isEmpty {
                Text("No live samples yet.")
                    .font(MusoptiTheme.caption)
                    .foregroundStyle(MusoptiTheme.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                Chart {
                    ForEach(Array(recordingManager.livePreviewSamples.enumerated()), id: \.offset) { index, point in
                        LineMark(
                            x: .value("Index", index),
                            y: .value("Magnitude", point.magnitude)
                        )
                        .foregroundStyle(MusoptiTheme.accent)
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine()
                            .foregroundStyle(MusoptiTheme.textTertiary)
                    }
                }
                .frame(height: 180)
            }
        }
        .padding(MusoptiTheme.mediumPadding)
        .background(MusoptiTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius))
    }

    private var actionButton: some View {
        Button {
            if recordingManager.isRecording {
                recordingManager.stopRecording(bleManager: bleManager)
            } else {
                recordingManager.startRecording(
                    exercise: selectedExercise,
                    sampleRateHz: sampleRateHz,
                    bleManager: bleManager
                )
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: recordingManager.isRecording ? "stop.fill" : "record.circle")
                    .font(.title2)
                Text(recordingManager.isRecording ? "Stop Recording" : "Start Recording")
                    .font(.headline)
            }
            .foregroundStyle(recordingManager.isRecording ? .white : .black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(recordingManager.isRecording ? .red : MusoptiTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(!recordingManager.isRecording && recordingManager.preflightIssue != nil)
    }

    private func recordingSummaryView(_ summary: RecordingSummary) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: MusoptiTheme.largePadding) {
                Text("Recording saved")
                    .font(MusoptiTheme.sectionTitle)
                    .foregroundStyle(MusoptiTheme.textPrimary)

                VStack(alignment: .leading, spacing: MusoptiTheme.smallPadding) {
                    summaryRow("Duration", value: summary.duration.formatted)
                    summaryRow("Samples", value: "\(summary.sampleCount)")
                    summaryRow("Requested rate", value: "\(summary.requestedSampleRateHz) Hz")
                    summaryRow(
                        "Observed rate",
                        value: summary.observedSampleRateHz.map { String(format: "%.0f Hz", $0) } ?? "Unavailable"
                    )
                }
                .padding(MusoptiTheme.mediumPadding)
                .background(MusoptiTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius))

                Spacer()
            }
            .padding(MusoptiTheme.largePadding)
            .background(MusoptiTheme.surfaceBackground)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        recordingManager.lastCompletedSummary = nil
                        dismiss()
                    }
                }
            }
        }
    }

    private func summaryRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(MusoptiTheme.textSecondary)
        }
    }

    private func updatePreflight() {
        recordingManager.preparePreflight(
            exercise: selectedExercise,
            sampleRateHz: sampleRateHz,
            bleManager: bleManager
        )
    }
}

private struct StatBox: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(MusoptiTheme.accent)
            Text(value)
                .font(MusoptiTheme.phaseLabel)
                .foregroundStyle(MusoptiTheme.textPrimary)
                .monospacedDigit()
            Text(title)
                .font(MusoptiTheme.caption)
                .foregroundStyle(MusoptiTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.3 : 1)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
