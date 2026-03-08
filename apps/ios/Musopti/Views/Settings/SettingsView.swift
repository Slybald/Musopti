import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppPreferences.self) private var preferences
    @Environment(BLEManager.self) private var bleManager
    @Environment(\.modelContext) private var modelContext

    @State private var showDeleteConfirmation = false
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []

    private let sampleRateOptions = [50, 100, 200]

    var body: some View {
        @Bindable var preferences = preferences

        NavigationStack {
            List {
                deviceSection
                sessionSection(preferences: $preferences)
                unitsSection(preferences: $preferences)
                catalogSection
                dataSection
                aboutSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: shareItems)
            }
            .alert("Delete All Data", isPresented: $showDeleteConfirmation) {
                Button("Delete Everything", role: .destructive) {
                    deleteAllData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all workout sessions, recordings, and custom exercises. This action cannot be undone.")
            }
        }
    }

    private var deviceSection: some View {
        Section("Device") {
            statusRow(
                title: "Connection",
                systemImage: "antenna.radiowaves.left.and.right",
                value: bleManager.deviceStatus.connectionState.title,
                tint: connectionColor
            )

            statusRow(
                title: "Bluetooth",
                systemImage: "bolt.horizontal.circle",
                value: bleManager.deviceStatus.bluetoothTitle
            )

            statusRow(
                title: "Signal Strength",
                systemImage: "wifi",
                value: bleManager.deviceStatus.rssi.map { "\($0) dBm" } ?? "Unavailable"
            )

            statusRow(
                title: "Config Sync",
                systemImage: "arrow.triangle.2.circlepath",
                value: bleManager.isConfigInSync ? "In sync" : "Config not synced",
                tint: bleManager.isConfigInSync ? MusoptiTheme.valid : MusoptiTheme.warning
            )

            statusRow(
                title: "Config Revision",
                systemImage: "number.circle",
                value: bleManager.deviceStatus.configRevision.map { String($0) } ?? "Unavailable"
            )

            statusRow(
                title: "Applied Sample Rate",
                systemImage: "metronome",
                value: bleManager.deviceStatus.appliedSampleRateHz.map { "\($0) Hz" } ?? "Unavailable"
            )

            statusRow(
                title: "Battery",
                systemImage: "battery.75percent",
                value: bleManager.deviceStatus.batteryPercent.map { "\($0)%" } ?? "Unavailable on current firmware"
            )

            statusRow(
                title: "Firmware",
                systemImage: "cpu",
                value: bleManager.deviceStatus.firmwareVersion?.title ?? "Unavailable on current firmware"
            )

            statusRow(
                title: "Last Status",
                systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                value: bleManager.deviceStatus.lastStatusAt?.shortRelativeTimestamp ?? "Unavailable"
            )

            if let error = bleManager.lastErrorMessage, !error.isEmpty {
                statusRow(
                    title: "Last Error",
                    systemImage: "exclamationmark.triangle",
                    value: error,
                    tint: MusoptiTheme.warning
                )
            }
        }
    }

    private func sessionSection(preferences: Bindable<AppPreferences>) -> some View {
        Section("Session") {
            Stepper(value: preferences.restTimerThreshold, in: 5...30) {
                HStack {
                    Label("Rest Timer", systemImage: "timer")
                    Spacer()
                    Text("\(self.preferences.restTimerThreshold)s")
                        .foregroundStyle(MusoptiTheme.textSecondary)
                        .monospacedDigit()
                }
            }

            HStack {
                Label("Default Sample Rate", systemImage: "metronome")
                Spacer()
                Picker("", selection: preferences.defaultSampleRateHz) {
                    ForEach(sampleRateOptions, id: \.self) { rate in
                        Text("\(rate) Hz").tag(rate)
                    }
                }
                .pickerStyle(.menu)
                .tint(MusoptiTheme.accent)
            }

            Toggle(isOn: preferences.showGraphByDefault) {
                Label("Show Graph by Default", systemImage: "chart.xyaxis.line")
            }

            Toggle(isOn: preferences.enableHaptics) {
                Label("Haptic Feedback", systemImage: "iphone.radiowaves.left.and.right")
            }

            Toggle(isOn: preferences.enableAudioCues) {
                Label("Audio Cues", systemImage: "speaker.wave.2")
            }

            Toggle(isOn: preferences.autoReconnect) {
                Label("Auto Reconnect", systemImage: "arrow.clockwise.circle")
            }
        }
    }

    private func unitsSection(preferences: Bindable<AppPreferences>) -> some View {
        Section("Units") {
            HStack {
                Label("Weight Unit", systemImage: "scalemass")
                Spacer()
                Picker("", selection: preferences.weightUnit) {
                    ForEach(WeightUnit.allCases) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }
        }
    }

    private var catalogSection: some View {
        Section("Exercise Catalog") {
            NavigationLink {
                CustomExerciseEditor()
            } label: {
                Label("Manage Custom Exercises", systemImage: "figure.strengthtraining.traditional")
            }
        }
    }

    private var dataSection: some View {
        Section("Data") {
            Button {
                exportAllHistory()
            } label: {
                Label("Export All History", systemImage: "square.and.arrow.up")
            }

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete All Data", systemImage: "trash")
                    .foregroundStyle(.red)
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Musopti - Strength Training Analysis")
                    .font(MusoptiTheme.bodyText)
                    .foregroundStyle(MusoptiTheme.textSecondary)
            }

            HStack {
                Text("Version")
                Spacer()
                Text(appVersion)
                    .foregroundStyle(MusoptiTheme.textSecondary)
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var connectionColor: Color {
        switch bleManager.connectionState {
        case .ready:
            return MusoptiTheme.valid
        case .connecting, .searching, .recovering:
            return MusoptiTheme.warning
        case .error:
            return MusoptiTheme.invalid
        case .offline:
            return MusoptiTheme.textTertiary
        }
    }

    private func statusRow(title: String, systemImage: String, value: String, tint: Color? = nil) -> some View {
        HStack(alignment: .top) {
            Label(title, systemImage: systemImage)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(tint ?? MusoptiTheme.textSecondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func exportAllHistory() {
        let descriptor = FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        guard let sessions = try? modelContext.fetch(descriptor) else { return }

        struct SessionExport: Codable {
            let id: String
            let templateName: String?
            let startedAt: Date
            let finishedAt: Date?
            let totalSets: Int
            let totalReps: Int
            let totalVolume: Double
            let holdSuccessRate: Double?
        }

        let exports = sessions.map { session in
            SessionExport(
                id: session.id.uuidString,
                templateName: session.templateName,
                startedAt: session.startedAt,
                finishedAt: session.finishedAt,
                totalSets: session.totalSets,
                totalReps: session.totalReps,
                totalVolume: session.totalVolume,
                holdSuccessRate: session.holdSuccessRate
            )
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let jsonData = try? encoder.encode(exports) else { return }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("musopti_history.json")
        try? jsonData.write(to: url)
        shareItems = [url]
        showShareSheet = true
    }

    private func deleteAllData() {
        try? modelContext.delete(model: WorkoutSession.self)
        try? modelContext.delete(model: IMURecording.self)

        let customDescriptor = FetchDescriptor<Exercise>(predicate: #Predicate { !$0.isBuiltIn })
        if let customExercises = try? modelContext.fetch(customDescriptor) {
            for exercise in customExercises {
                modelContext.delete(exercise)
            }
        }

        try? modelContext.save()

        let recordingsDirectory = RecordingManager.recordingsDirectory
        try? FileManager.default.removeItem(at: recordingsDirectory)
    }
}
