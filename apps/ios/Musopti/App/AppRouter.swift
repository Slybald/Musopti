import Foundation
import Observation

enum AppTab: Hashable {
    case session
    case workouts
    case history
    case recordings
    case settings
}

enum AppSheet: String, Identifiable {
    case deviceStatus

    var id: String { rawValue }
}

@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .session
    var presentedSheet: AppSheet?
    var highlightedSessionID: UUID?
    var highlightedRecordingID: UUID?

    func navigateToSession() {
        selectedTab = .session
    }

    func navigateToWorkouts() {
        selectedTab = .workouts
    }

    func navigateToHistory(sessionID: UUID? = nil) {
        highlightedSessionID = sessionID
        selectedTab = .history
    }

    func navigateToRecording(recordingID: UUID? = nil) {
        highlightedRecordingID = recordingID
        selectedTab = .recordings
    }

    func navigateToSettings() {
        selectedTab = .settings
    }

    func presentDeviceStatus() {
        presentedSheet = .deviceStatus
    }

    func dismissSheet() {
        presentedSheet = nil
    }
}
