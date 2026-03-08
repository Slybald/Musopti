import SwiftUI
import SwiftData

struct RecordingsView: View {
    @Environment(AppRouter.self) private var router
    @Environment(RecordingManager.self) private var recordingManager
    @Query(sort: \IMURecording.startedAt, order: .reverse) private var recordings: [IMURecording]

    @State private var navigationPath: [UUID] = []
    @State private var showRecordingSheet = false
    @State private var selectedRecordings = Set<PersistentIdentifier>()
    @State private var isSelecting = false
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if recordings.isEmpty {
                    emptyState
                } else {
                    recordingList
                }
            }
            .navigationTitle("Recordings")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !recordings.isEmpty {
                        Button(isSelecting ? "Done" : "Select") {
                            withAnimation {
                                isSelecting.toggle()
                                if !isSelecting {
                                    selectedRecordings.removeAll()
                                }
                            }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showRecordingSheet = true
                    } label: {
                        Label("New Recording", systemImage: "plus.circle.fill")
                    }
                    .tint(MusoptiTheme.accent)
                }
            }
            .sheet(isPresented: $showRecordingSheet) {
                RecordingLiveView()
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: shareItems)
            }
            .navigationDestination(for: UUID.self) { recordingID in
                if let recording = recordings.first(where: { $0.id == recordingID }) {
                    RecordingPreviewView(recording: recording)
                }
            }
        }
        .onChange(of: router.highlightedRecordingID) { _, recordingID in
            guard let recordingID else { return }
            navigationPath = [recordingID]
            router.highlightedRecordingID = nil
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Recordings", systemImage: "waveform.slash")
        } description: {
            Text("Record raw IMU data for analysis and model training.")
        } actions: {
            Button("New Recording") {
                showRecordingSheet = true
            }
            .buttonStyle(.borderedProminent)
            .tint(MusoptiTheme.accent)
        }
    }

    private var recordingList: some View {
        List(selection: isSelecting ? $selectedRecordings : nil) {
            ForEach(recordings) { recording in
                NavigationLink(value: recording.id) {
                    RecordingRowView(recording: recording)
                }
                .listRowBackground(MusoptiTheme.cardBackground)
            }
            .onDelete(perform: deleteRecordings)
        }
        .listStyle(.plain)
        .safeAreaInset(edge: .bottom) {
            if isSelecting && !selectedRecordings.isEmpty {
                exportBar
            }
        }
    }

    private var exportBar: some View {
        Menu {
            Button {
                exportSelected(format: .csv)
            } label: {
                Label("Export as CSV", systemImage: "tablecells")
            }

            Button {
                exportSelected(format: .binary)
            } label: {
                Label("Export binary files", systemImage: "doc")
            }

            Button {
                exportSelected(format: .datasetBundle)
            } label: {
                Label("Export dataset bundle", systemImage: "shippingbox")
            }
        } label: {
            Label(
                "Export \(selectedRecordings.count) Recording\(selectedRecordings.count == 1 ? "" : "s")",
                systemImage: "square.and.arrow.up"
            )
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(MusoptiTheme.accent)
        .padding()
        .background(.ultraThinMaterial)
    }

    private func deleteRecordings(at offsets: IndexSet) {
        for index in offsets {
            recordingManager.deleteRecording(recordings[index])
        }
    }

    private func exportSelected(format: RecordingExportFormat) {
        let selected = recordings.filter { selectedRecordings.contains($0.persistentModelID) }
        let urls = recordingManager.exportSelected(selected, format: format)

        if !urls.isEmpty {
            shareItems = urls
            showShareSheet = true
        }
    }
}

struct RecordingRowView: View {
    @Environment(ExerciseCatalog.self) private var exerciseCatalog
    let recording: IMURecording

    private var resolvedExercise: Exercise? {
        guard let exerciseID = recording.exerciseID else { return nil }
        return exerciseCatalog.exercise(id: exerciseID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                HStack(spacing: 10) {
                    if let resolvedExercise {
                        ExerciseIconView(exercise: resolvedExercise, size: 38)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(recording.exerciseName)
                            .font(MusoptiTheme.phaseLabel)
                            .foregroundStyle(MusoptiTheme.textPrimary)

                        if let resolvedExercise {
                            Text(resolvedExercise.equipmentDisplayName)
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

            HStack(spacing: 12) {
                if let duration = recording.duration {
                    Label(duration.formatted, systemImage: "clock")
                }
                Label("\(recording.sampleCount) samples", systemImage: "waveform")
                Label("\(recording.sampleRateHz) Hz", systemImage: "metronome")
            }
            .font(MusoptiTheme.caption)
            .foregroundStyle(MusoptiTheme.textSecondary)

            HStack {
                Text(recording.estimatedFileSize.formattedFileSize)
                    .font(MusoptiTheme.caption)
                    .foregroundStyle(MusoptiTheme.textTertiary)

                if let observedSampleRate = recording.observedSampleRate {
                    Text("•")
                        .foregroundStyle(MusoptiTheme.textTertiary)
                    Text(String(format: "%.0f Hz observed", observedSampleRate))
                        .font(MusoptiTheme.caption)
                        .foregroundStyle(MusoptiTheme.textTertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
