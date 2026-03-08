import CoreBluetooth
import SwiftUI

struct ConnectionView: View {
    @Environment(BLEManager.self) private var bleManager

    @State private var isTroubleshootingExpanded = false
    @State private var showScanTimeoutHint = false

    var onSkip: (() -> Void)?

    init(onSkip: (() -> Void)? = nil) {
        self.onSkip = onSkip
    }

    var body: some View {
        ZStack {
            MusoptiTheme.surfaceBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    topSection
                    actionRow
                    deviceListSection
                    Spacer(minLength: MusoptiTheme.largePadding)
                    troubleshootingSection
                    skipButton
                }
                .padding(.horizontal, MusoptiTheme.largePadding)
            }

            if bleManager.connectionState == .connecting || bleManager.connectionState == .recovering {
                connectingOverlay
            }
        }
        .task {
            restartScan()
        }
    }

    // MARK: - Top Section

    private var topSection: some View {
        VStack(spacing: MusoptiTheme.mediumPadding) {
            Image(systemName: "sensor.tag.radiowaves.forward")
                .font(.system(size: 80))
                .foregroundStyle(MusoptiTheme.accent)
                .symbolEffect(.pulse, options: .repeating, value: bleManager.connectionState == .searching)

            Text("Musopti")
                .font(.largeTitle.bold())
                .foregroundStyle(MusoptiTheme.textPrimary)

            subtitleView

            if let lastKnownDeviceName = bleManager.deviceStatus.lastKnownDeviceName {
                Text("Last known device: \(lastKnownDeviceName)")
                    .font(MusoptiTheme.caption)
                    .foregroundStyle(MusoptiTheme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, bleManager.peripherals.isEmpty ? 72 : MusoptiTheme.largePadding)
        .padding(.bottom, MusoptiTheme.largePadding)
    }

    @ViewBuilder
    private var subtitleView: some View {
        switch bleManager.bluetoothState {
        case .poweredOff:
            statusMessage("Turn on Bluetooth to connect your Musopti module.")
        case .resetting:
            statusMessage("Bluetooth is resetting. The app will recover automatically.")
        case .unauthorized:
            statusMessage("Bluetooth permission is required.")
        case .unsupported:
            statusMessage("Bluetooth is unsupported on this device.")
        case .poweredOn:
            switch bleManager.connectionState {
            case .searching:
                VStack(spacing: MusoptiTheme.smallPadding) {
                    Text("Searching for nearby Musopti devices…")
                        .font(MusoptiTheme.bodyText)
                        .foregroundStyle(MusoptiTheme.textSecondary)
                    ProgressView()
                        .tint(MusoptiTheme.accent)
                }
            case .recovering:
                statusMessage("Trying to reconnect to your last device.")
            default:
                statusMessage("Connect once, then the app stays usable offline.")
            }
        default:
            statusMessage("Preparing Bluetooth…")
        }
    }

    private func statusMessage(_ text: String) -> some View {
        Text(text)
            .font(MusoptiTheme.bodyText)
            .foregroundStyle(MusoptiTheme.textSecondary)
            .multilineTextAlignment(.center)
    }

    // MARK: - Actions

    private var actionRow: some View {
        HStack(spacing: MusoptiTheme.smallPadding) {
            Button {
                restartScan()
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(MusoptiTheme.accent)
            .disabled(bleManager.bluetoothState != .poweredOn)

            Button {
                onSkip?()
            } label: {
                Label("Offline Mode", systemImage: "wifi.slash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(MusoptiTheme.textSecondary)
        }
        .padding(.bottom, MusoptiTheme.mediumPadding)
    }

    // MARK: - Device List

    @ViewBuilder
    private var deviceListSection: some View {
        if !bleManager.peripherals.isEmpty {
            VStack(spacing: MusoptiTheme.smallPadding) {
                ForEach(bleManager.peripherals) { peripheral in
                    PeripheralCard(
                        peripheral: peripheral,
                        isLastKnown: peripheral.id == bleManager.peripherals.first?.id
                            && peripheral.id == lastKnownPeripheralID
                    ) {
                        bleManager.connect(to: peripheral)
                    }
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.95).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: bleManager.peripherals.map(\.id))
        } else {
            emptyScanState
        }
    }

    private var emptyScanState: some View {
        VStack(alignment: .leading, spacing: MusoptiTheme.smallPadding) {
            Label(emptyStateTitle, systemImage: emptyStateIcon)
                .font(MusoptiTheme.bodyText.weight(.semibold))
                .foregroundStyle(MusoptiTheme.textPrimary)

            Text(emptyStateDescription)
                .font(MusoptiTheme.caption)
                .foregroundStyle(MusoptiTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MusoptiTheme.mediumPadding)
        .background(MusoptiTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius))
    }

    private var emptyStateTitle: String {
        if bleManager.bluetoothState == .poweredOff {
            return "Bluetooth is turned off"
        }
        if showScanTimeoutHint {
            return "No device found yet"
        }
        return "Waiting for a device"
    }

    private var emptyStateDescription: String {
        if bleManager.bluetoothState == .poweredOff {
            return "Enable Bluetooth in Control Center or Settings, then rescan."
        }
        if showScanTimeoutHint {
            return "Make sure the module is on, nearby, and advertising before trying again."
        }
        return "Your Musopti module will appear here as soon as it is detected."
    }

    private var emptyStateIcon: String {
        if bleManager.bluetoothState == .poweredOff {
            return "bolt.slash"
        }
        return showScanTimeoutHint ? "sensor.tag.radiowaves.forward.fill" : "dot.radiowaves.left.and.right"
    }

    // MARK: - Connecting Overlay

    private var connectingOverlay: some View {
        Color.black.opacity(0.72)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: MusoptiTheme.mediumPadding) {
                    ProgressView()
                        .scaleEffect(1.4)
                        .tint(MusoptiTheme.accent)
                    Text(bleManager.connectionState == .recovering ? "Reconnecting…" : "Connecting…")
                        .font(MusoptiTheme.sectionTitle)
                        .foregroundStyle(MusoptiTheme.textPrimary)
                }
            }
    }

    // MARK: - Troubleshooting

    private var troubleshootingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isTroubleshootingExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("Troubleshooting")
                        .font(MusoptiTheme.caption)
                        .foregroundStyle(MusoptiTheme.textSecondary)
                    Spacer()
                    Image(systemName: isTroubleshootingExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MusoptiTheme.textTertiary)
                }
                .padding(.vertical, MusoptiTheme.smallPadding)
            }
            .buttonStyle(.plain)

            if isTroubleshootingExpanded {
                VStack(alignment: .leading, spacing: MusoptiTheme.smallPadding) {
                    troubleshootingItem("Make sure the Musopti device is turned on.")
                    troubleshootingItem("Stay within 5 meters of the module.")
                    troubleshootingItem("Rescan after enabling Bluetooth.")
                }
                .padding(.bottom, MusoptiTheme.smallPadding)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.top, MusoptiTheme.largePadding)
        .padding(.bottom, MusoptiTheme.largePadding)
    }

    private func troubleshootingItem(_ text: String) -> some View {
        Text("• \(text)")
            .font(MusoptiTheme.caption)
            .foregroundStyle(MusoptiTheme.textTertiary)
    }

    // MARK: - Skip Button

    private var skipButton: some View {
        Button {
            onSkip?()
        } label: {
            Text("Continue without device")
                .font(MusoptiTheme.bodyText)
                .foregroundStyle(MusoptiTheme.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 32)
    }

    // MARK: - Scan Control

    private func restartScan() {
        showScanTimeoutHint = false
        bleManager.startScanning()

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            if bleManager.peripherals.isEmpty && bleManager.connectionState == .searching {
                showScanTimeoutHint = true
            }
        }
    }

    private var lastKnownPeripheralID: UUID? {
        guard let raw = UserDefaults.standard.string(forKey: "musopti.lastPeripheralID") else { return nil }
        return UUID(uuidString: raw)
    }
}

private struct PeripheralCard: View {
    let peripheral: DiscoveredPeripheral
    let isLastKnown: Bool
    let onConnect: () -> Void

    var body: some View {
        Button(action: onConnect) {
            HStack(spacing: MusoptiTheme.mediumPadding) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(peripheral.name)
                            .font(.headline)
                            .foregroundStyle(MusoptiTheme.textPrimary)
                        if isLastKnown {
                            Text("LAST DEVICE")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(MusoptiTheme.accent)
                                .clipShape(Capsule())
                        }
                    }
                    SignalBarsView(rssi: peripheral.rssi)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("Connect")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MusoptiTheme.accent)
            }
            .padding(MusoptiTheme.mediumPadding)
            .background(MusoptiTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius))
        }
        .buttonStyle(.plain)
    }
}

private struct SignalBarsView: View {
    let rssi: Int

    private var bars: Int {
        if rssi > -50 { return 3 }
        if rssi > -70 { return 2 }
        return 1
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(index < bars ? MusoptiTheme.accent : MusoptiTheme.textTertiary)
                    .frame(width: 5, height: CGFloat(6 + index * 4))
            }
        }
    }
}
