import SwiftUI

struct DeviceStatusSheetView: View {
    @Environment(AppRouter.self) private var router
    @Environment(BLEManager.self) private var bleManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Connection") {
                    statusRow("State", value: bleManager.deviceStatus.connectionState.title)
                    statusRow("Bluetooth", value: bleManager.deviceStatus.bluetoothTitle)
                    statusRow("Last Device", value: bleManager.deviceStatus.lastKnownDeviceName ?? "Unavailable")
                    statusRow("Signal", value: bleManager.deviceStatus.rssi.map { "\($0) dBm" } ?? "Unavailable")
                    statusRow("Last Status", value: bleManager.deviceStatus.lastStatusAt?.shortRelativeTimestamp ?? "Unavailable")
                }

                Section("Config") {
                    statusRow("Config Sync", value: bleManager.isConfigInSync ? "In sync" : "Config not synced")
                    statusRow("Revision", value: bleManager.deviceStatus.configRevision.map { String($0) } ?? "Unavailable")
                    statusRow("Mode", value: deviceModeLabel)
                    statusRow("Exercise", value: exerciseLabel)
                    statusRow("Sample Rate", value: bleManager.deviceStatus.appliedSampleRateHz.map { "\($0) Hz" } ?? "Unavailable")
                    statusRow("Last Sync", value: bleManager.deviceStatus.lastConfigSyncAt?.shortRelativeTimestamp ?? "Unavailable")
                }

                Section("Diagnostics") {
                    statusRow("Motion State", value: bleManager.deviceStatus.motionPhase?.label ?? "Unavailable")
                    statusRow("Last Event", value: bleManager.deviceStatus.lastEventAt?.shortRelativeTimestamp ?? "Unavailable")
                    statusRow("Battery", value: bleManager.deviceStatus.batteryPercent.map { "\($0)%" } ?? "Unavailable on current firmware")
                    statusRow("Firmware", value: bleManager.deviceStatus.firmwareVersion?.title ?? "Unavailable on current firmware")
                    statusRow("IMU Source", value: bleManager.deviceStatus.isIMUSimulated ? "Simulated" : "Hardware")
                    statusRow("Display", value: bleManager.deviceStatus.isDisplaySimulated ? "Simulated" : "Hardware")
                    statusRow("Audio", value: bleManager.deviceStatus.isAudioSimulated ? "Simulated" : "Hardware")
                    if let error = bleManager.lastErrorMessage, !error.isEmpty {
                        statusRow("Last Error", value: error)
                    }
                }
            }
            .navigationTitle("Device Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        router.dismissSheet()
                        dismiss()
                    }
                }
            }
        }
    }

    private var deviceModeLabel: String {
        switch bleManager.deviceStatus.deviceMode {
        case .idle:
            return "Idle"
        case .detection:
            return "Detection"
        case .recording:
            return "Recording"
        case .none:
            return "Unavailable"
        }
    }

    private var exerciseLabel: String {
        switch bleManager.deviceStatus.firmwareExercise {
        case .generic:
            return "Generic"
        case .benchPress:
            return "Bench Press"
        case .squat:
            return "Squat"
        case .deadlift:
            return "Deadlift"
        case .custom:
            return "Custom"
        case .none:
            return "Unavailable"
        }
    }

    private func statusRow(_ title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(MusoptiTheme.textSecondary)
                .multilineTextAlignment(.trailing)
        }
    }
}
