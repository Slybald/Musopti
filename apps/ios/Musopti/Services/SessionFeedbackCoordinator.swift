import AudioToolbox
import UIKit

@MainActor
final class SessionFeedbackCoordinator {
    private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let notificationGenerator = UINotificationFeedbackGenerator()

    private var enableHaptics = true
    private var enableAudioCues = false

    func applyPreferences(_ preferences: AppPreferences) {
        enableHaptics = preferences.enableHaptics
        enableAudioCues = preferences.enableAudioCues
        impactGenerator.prepare()
        notificationGenerator.prepare()
    }

    func playRepComplete() {
        if enableHaptics {
            impactGenerator.impactOccurred()
            impactGenerator.prepare()
        }
        if enableAudioCues {
            AudioServicesPlaySystemSound(1104)
        }
    }

    func playHold(valid: Bool) {
        if enableHaptics {
            notificationGenerator.notificationOccurred(valid ? .success : .warning)
            notificationGenerator.prepare()
        }
        if enableAudioCues {
            AudioServicesPlaySystemSound(valid ? 1113 : 1053)
        }
    }
}
