import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppPreferences.self) private var preferences
    @Environment(BLEManager.self) private var bleManager
    @Environment(SessionManager.self) private var sessionManager
    @Environment(StatsEngine.self) private var statsEngine
    @Environment(ExerciseCatalog.self) private var exerciseCatalog
    @Environment(RecordingManager.self) private var recordingManager
    @Environment(\.modelContext) private var modelContext

    private var showMainApp: Bool {
        preferences.hasCompletedConnectionGate || bleManager.deviceStatus.isReady
    }

    var body: some View {
        Group {
            if showMainApp {
                MainTabView()
            } else {
                ConnectionView {
                    withAnimation(.easeInOut) {
                        preferences.hasCompletedConnectionGate = true
                    }
                }
            }
        }
        .animation(.easeInOut, value: showMainApp)
        .onAppear {
            sessionManager.configure(modelContext: modelContext)
            statsEngine.configure(modelContext: modelContext)
            exerciseCatalog.configure(modelContext: modelContext)
            recordingManager.configure(modelContext: modelContext)
            exerciseCatalog.seedIfNeeded()
            applyPreferences()
            bleManager.onEventReceived = { event in
                Task { @MainActor in
                    sessionManager.handleEvent(event)
                }
            }
        }
        .onChange(of: bleManager.deviceStatus.isReady) { _, isReady in
            if isReady {
                preferences.hasCompletedConnectionGate = true
            }
        }
        .onChange(of: preferences.restTimerThreshold) { _, _ in
            applyPreferences()
        }
        .onChange(of: preferences.defaultSampleRateHz) { _, _ in
            applyPreferences()
        }
        .onChange(of: preferences.weightUnit) { _, _ in
            applyPreferences()
        }
        .onChange(of: preferences.showGraphByDefault) { _, _ in
            applyPreferences()
        }
        .onChange(of: preferences.enableHaptics) { _, _ in
            applyPreferences()
        }
        .onChange(of: preferences.enableAudioCues) { _, _ in
            applyPreferences()
        }
        .onChange(of: preferences.autoReconnect) { _, _ in
            applyPreferences()
        }
    }

    private func applyPreferences() {
        sessionManager.applyPreferences(preferences)
        recordingManager.applyPreferences(preferences)
        bleManager.setAutoReconnectEnabled(preferences.autoReconnect)
        _ = router
    }
}
