import SwiftUI

struct DeviceBanner: View {
    @Environment(AppRouter.self) private var router
    @Environment(BLEManager.self) private var bleManager

    var body: some View {
        VStack {
            if shouldShowBanner {
                Button {
                    router.presentDeviceStatus()
                } label: {
                    HStack(spacing: 10) {
                        if bleManager.deviceStatus.isRecovering {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: bannerIcon)
                                .font(.caption.weight(.bold))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(bannerTitle)
                                .font(MusoptiTheme.caption.weight(.semibold))
                                .foregroundStyle(.white)
                            Text(bannerSubtitle)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.82))
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, MusoptiTheme.mediumPadding)
                    .padding(.vertical, 10)
                    .background(bannerBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, MusoptiTheme.mediumPadding)
                    .padding(.top, 8)
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer()
        }
        .animation(.easeInOut(duration: 0.25), value: shouldShowBanner)
    }

    private var shouldShowBanner: Bool {
        bleManager.connectionState == .recovering
            || bleManager.connectionState == .offline
            || bleManager.connectionState == .error
            || !bleManager.isConfigInSync
            || bleManager.deviceStatus.hasSimulatedPeripherals
    }

    private var bannerTitle: String {
        if bleManager.deviceStatus.hasSimulatedPeripherals {
            return "Simulated firmware active"
        }
        if !bleManager.isConfigInSync {
            return "Config not synced"
        }

        switch bleManager.connectionState {
        case .recovering:
            return "Reconnecting…"
        case .error:
            return "Device error"
        case .offline:
            return "Device offline"
        default:
            return "Device status"
        }
    }

    private var bannerSubtitle: String {
        if bleManager.deviceStatus.hasSimulatedPeripherals {
            return "Using \(bleManager.deviceStatus.simulatedComponentsLabel). Check the device status before validating hardware behavior."
        }
        if !bleManager.isConfigInSync {
            if let revision = bleManager.deviceStatus.configRevision,
               let lastStatus = bleManager.deviceStatus.lastStatusAt {
                return "Revision \(revision) • status \(lastStatus.shortRelativeTimestamp)"
            }
            return bleManager.deviceStatus.lastConfigSyncAt.map { "Last sync \($0.shortRelativeTimestamp)" } ?? "Tap to review device status"
        }

        if let lastStatus = bleManager.deviceStatus.lastStatusAt {
            return "Last status: \(lastStatus.shortRelativeTimestamp)"
        }

        if let deviceName = bleManager.deviceStatus.lastKnownDeviceName {
            return "Last known device: \(deviceName)"
        }

        return "Tap to open device status"
    }

    private var bannerIcon: String {
        if bleManager.deviceStatus.hasSimulatedPeripherals {
            return "wrench.and.screwdriver.fill"
        }
        if !bleManager.isConfigInSync {
            return "exclamationmark.triangle.fill"
        }
        if bleManager.connectionState == .offline {
            return "wifi.slash"
        }
        return "sensor.tag.radiowaves.forward"
    }

    private var bannerBackground: some ShapeStyle {
        if bleManager.deviceStatus.hasSimulatedPeripherals {
            return MusoptiTheme.warning.gradient
        }
        if !bleManager.isConfigInSync {
            return MusoptiTheme.warning.gradient
        }
        if bleManager.connectionState == .error {
            return MusoptiTheme.invalid.gradient
        }
        return MusoptiTheme.warning.gradient
    }
}

struct DeviceBannerModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            DeviceBanner()
        }
    }
}

extension View {
    func deviceBanner() -> some View {
        modifier(DeviceBannerModifier())
    }
}
