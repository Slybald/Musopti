import Foundation

enum BLESyncEvaluator {
    static func isInSync(
        sent: MusoptiConfig?,
        readBack: MusoptiConfig?,
        status: MusoptiStatus?
    ) -> Bool {
        guard let readBack, let status else {
            return sent == nil
        }

        if let sent, sent != readBack {
            return false
        }

        return statusMatchesConfig(status, config: readBack)
    }

    static func statusMatchesConfig(_ status: MusoptiStatus, config: MusoptiConfig) -> Bool {
        status.deviceMode == config.deviceMode &&
        status.exerciseType == config.exerciseType &&
        status.sampleRateHz == config.sampleRateHz
    }

    static func syncErrorMessage(
        sent: MusoptiConfig?,
        readBack: MusoptiConfig?,
        status: MusoptiStatus?
    ) -> String? {
        guard sent != nil else { return nil }
        return isInSync(sent: sent, readBack: readBack, status: status)
            ? nil
            : "Device config is not synced with the app."
    }
}
