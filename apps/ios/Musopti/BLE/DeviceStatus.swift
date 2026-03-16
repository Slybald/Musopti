import CoreBluetooth
import Foundation

enum DeviceConnectionState: String, Equatable {
    case offline
    case searching
    case connecting
    case ready
    case recovering
    case error

    var title: String {
        switch self {
        case .offline: return "Offline"
        case .searching: return "Searching"
        case .connecting: return "Connecting"
        case .ready: return "Ready"
        case .recovering: return "Recovering"
        case .error: return "Error"
        }
    }
}

struct DeviceStatus: Equatable {
    var connectionState: DeviceConnectionState
    var bluetoothState: CBManagerState
    var rssi: Int?
    var batteryPercent: Int?
    var deviceMode: MusoptiDeviceMode?
    var firmwareExercise: MusoptiExerciseType?
    var motionPhase: MotionPhase?
    var appliedSampleRateHz: Int?
    var configRevision: Int?
    var firmwareVersion: MusoptiFirmwareVersion?
    var isIMUSimulated: Bool
    var isDisplaySimulated: Bool
    var isAudioSimulated: Bool
    var lastEventAt: Date?
    var lastStatusAt: Date?
    var isRecovering: Bool
    var lastKnownDeviceName: String?
    var lastConfigSyncAt: Date?

    static let placeholder = DeviceStatus(
        connectionState: .offline,
        bluetoothState: .unknown,
        rssi: nil,
        batteryPercent: nil,
        deviceMode: nil,
        firmwareExercise: nil,
        motionPhase: nil,
        appliedSampleRateHz: nil,
        configRevision: nil,
        firmwareVersion: nil,
        isIMUSimulated: false,
        isDisplaySimulated: false,
        isAudioSimulated: false,
        lastEventAt: nil,
        lastStatusAt: nil,
        isRecovering: false,
        lastKnownDeviceName: nil,
        lastConfigSyncAt: nil
    )

    var isReady: Bool {
        connectionState == .ready && bluetoothState == .poweredOn
    }

    var hasSimulatedPeripherals: Bool {
        isIMUSimulated || isDisplaySimulated || isAudioSimulated
    }

    var simulatedComponentsLabel: String {
        var components: [String] = []
        if isIMUSimulated {
            components.append("IMU")
        }
        if isDisplaySimulated {
            components.append("display")
        }
        if isAudioSimulated {
            components.append("audio")
        }
        return components.joined(separator: ", ")
    }

    var bluetoothTitle: String {
        switch bluetoothState {
        case .poweredOn: return "Bluetooth on"
        case .poweredOff: return "Bluetooth off"
        case .resetting: return "Bluetooth resetting"
        case .unauthorized: return "Bluetooth unauthorized"
        case .unsupported: return "Bluetooth unsupported"
        case .unknown: return "Bluetooth unknown"
        @unknown default: return "Bluetooth unavailable"
        }
    }
}
