import SwiftUI
import SwiftData

@main
struct MusoptiApp: App {
    @State private var router = AppRouter()
    @State private var preferences = AppPreferences()
    @State private var bleManager = BLEManager()
    @State private var sessionManager = SessionManager()
    @State private var statsEngine = StatsEngine()
    @State private var exerciseCatalog = ExerciseCatalog()
    @State private var recordingManager = RecordingManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(router)
                .environment(preferences)
                .environment(bleManager)
                .environment(sessionManager)
                .environment(statsEngine)
                .environment(exerciseCatalog)
                .environment(recordingManager)
                .preferredColorScheme(.dark)
                .onAppear {
                    bleManager.onEventReceived = { [weak sessionManager] event in
                        Task { @MainActor in
                            sessionManager?.handleEvent(event)
                        }
                    }
                }
        }
        .modelContainer(for: [
            Exercise.self,
            WorkoutTemplate.self,
            WorkoutSession.self,
            IMURecording.self,
        ])
    }
}
