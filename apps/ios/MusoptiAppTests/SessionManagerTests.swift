import Foundation
import Testing
@testable import Musopti

@MainActor
struct SessionManagerTests {
    @Test func applyPreferences_updatesRestTimeout() async throws {
        let manager = SessionManager()
        let defaults = UserDefaults(suiteName: "SessionManagerTests.applyPreferences")!
        defaults.removePersistentDomain(forName: "SessionManagerTests.applyPreferences")
        let preferences = AppPreferences(defaults: defaults)
        preferences.restTimerThreshold = 14

        manager.applyPreferences(preferences)

        #expect(manager.restTimeoutSeconds == 14)
    }

    @Test func handleEvents_updatesSetSummaryAndHoldFeedback() async throws {
        let manager = SessionManager()
        let exercise = Exercise(
            name: "Bench Press",
            category: .chest,
            muscleGroup: "Chest",
            equipmentType: "Barbell",
            detectionProfile: .benchPress
        )

        manager.selectExercise(exercise)
        manager.startSession()

        manager.handleEvent(
            MusoptiEvent(
                version: 2,
                eventType: .holdResult,
                state: 2,
                flags: 0x01,
                repCount: 0,
                exerciseType: .benchPress,
                deviceMode: .detection,
                holdDurationMs: 3000
            )
        )
        manager.handleEvent(
            MusoptiEvent(
                version: 2,
                eventType: .repComplete,
                state: 4,
                flags: 0x01,
                repCount: 1,
                exerciseType: .benchPress,
                deviceMode: .detection,
                holdDurationMs: 3000
            )
        )

        #expect(manager.currentSetReps == 1)
        #expect(manager.currentSetSummary?.reps == 1)
        #expect(manager.currentSetSummary?.setNumber == 1)
        #expect(manager.currentSetSummary?.holdSuccessRate == 1)
        #expect(manager.lastFeedback?.title == "Rep counted")
    }
}
