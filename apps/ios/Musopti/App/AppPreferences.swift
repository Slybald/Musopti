import Foundation
import Observation

enum WeightUnit: String, CaseIterable, Identifiable {
    case kg
    case lbs

    var id: String { rawValue }
}

enum HistorySessionFilter: String, CaseIterable, Identifiable {
    case all
    case freeform
    case template

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .freeform: return "Freeform"
        case .template: return "Templates"
        }
    }
}

@MainActor
@Observable
final class AppPreferences {
    private enum Keys {
        static let restTimerThreshold = "musopti.preferences.restTimerThreshold"
        static let defaultSampleRateHz = "musopti.preferences.defaultSampleRateHz"
        static let weightUnit = "musopti.preferences.weightUnit"
        static let showGraphByDefault = "musopti.preferences.showGraphByDefault"
        static let enableHaptics = "musopti.preferences.enableHaptics"
        static let enableAudioCues = "musopti.preferences.enableAudioCues"
        static let autoReconnect = "musopti.preferences.autoReconnect"
        static let preferredHistoryRange = "musopti.preferences.preferredHistoryRange"
        static let preferredHistoryExerciseID = "musopti.preferences.preferredHistoryExerciseID"
        static let preferredHistoryFilter = "musopti.preferences.preferredHistoryFilter"
        static let hasCompletedConnectionGate = "musopti.preferences.hasCompletedConnectionGate"
    }

    private let defaults: UserDefaults
    private let supportedSampleRates = [50, 100, 200]

    var restTimerThreshold: Int {
        didSet { defaults.set(restTimerThreshold, forKey: Keys.restTimerThreshold) }
    }

    var defaultSampleRateHz: Int {
        didSet {
            if !supportedSampleRates.contains(defaultSampleRateHz) {
                defaultSampleRateHz = 100
            }
            defaults.set(defaultSampleRateHz, forKey: Keys.defaultSampleRateHz)
        }
    }

    var weightUnit: WeightUnit {
        didSet { defaults.set(weightUnit.rawValue, forKey: Keys.weightUnit) }
    }

    var showGraphByDefault: Bool {
        didSet { defaults.set(showGraphByDefault, forKey: Keys.showGraphByDefault) }
    }

    var enableHaptics: Bool {
        didSet { defaults.set(enableHaptics, forKey: Keys.enableHaptics) }
    }

    var enableAudioCues: Bool {
        didSet { defaults.set(enableAudioCues, forKey: Keys.enableAudioCues) }
    }

    var autoReconnect: Bool {
        didSet { defaults.set(autoReconnect, forKey: Keys.autoReconnect) }
    }

    var preferredHistoryRange: DateRange {
        didSet { defaults.set(preferredHistoryRange.rawValue, forKey: Keys.preferredHistoryRange) }
    }

    var preferredHistoryExerciseID: String {
        didSet { defaults.set(preferredHistoryExerciseID, forKey: Keys.preferredHistoryExerciseID) }
    }

    var preferredHistoryFilter: HistorySessionFilter {
        didSet { defaults.set(preferredHistoryFilter.rawValue, forKey: Keys.preferredHistoryFilter) }
    }

    var hasCompletedConnectionGate: Bool {
        didSet { defaults.set(hasCompletedConnectionGate, forKey: Keys.hasCompletedConnectionGate) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let sampleRate = defaults.integer(forKey: Keys.defaultSampleRateHz)
        let rangeRaw = defaults.string(forKey: Keys.preferredHistoryRange)
        let weightRaw = defaults.string(forKey: Keys.weightUnit)
        let filterRaw = defaults.string(forKey: Keys.preferredHistoryFilter)

        restTimerThreshold = defaults.object(forKey: Keys.restTimerThreshold) as? Int ?? 8
        defaultSampleRateHz = supportedSampleRates.contains(sampleRate) ? sampleRate : 100
        weightUnit = WeightUnit(rawValue: weightRaw ?? "") ?? .kg
        showGraphByDefault = defaults.object(forKey: Keys.showGraphByDefault) as? Bool ?? true
        enableHaptics = defaults.object(forKey: Keys.enableHaptics) as? Bool ?? true
        enableAudioCues = defaults.object(forKey: Keys.enableAudioCues) as? Bool ?? false
        autoReconnect = defaults.object(forKey: Keys.autoReconnect) as? Bool ?? true
        preferredHistoryRange = DateRange(rawValue: rangeRaw ?? "") ?? .oneMonth
        preferredHistoryExerciseID = defaults.string(forKey: Keys.preferredHistoryExerciseID) ?? ""
        preferredHistoryFilter = HistorySessionFilter(rawValue: filterRaw ?? "") ?? .all
        hasCompletedConnectionGate = defaults.object(forKey: Keys.hasCompletedConnectionGate) as? Bool ?? false
    }
}
