import SwiftUI

struct RestTimerView: View {
    @Environment(SessionManager.self) private var sessionManager
    @State private var pulse = false

    var body: some View {
        VStack(spacing: MusoptiTheme.smallPadding) {
            Text("REST")
                .font(MusoptiTheme.caption)
                .foregroundStyle(MusoptiTheme.textSecondary)
                .textCase(.uppercase)
                .tracking(2)

            Text(formattedTime)
                .font(MusoptiTheme.timer)
                .foregroundStyle(MusoptiTheme.textPrimary)
                .contentTransition(.numericText())
                .animation(.easeInOut, value: sessionManager.restTimerSeconds)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MusoptiTheme.mediumPadding)
        .background(MusoptiTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius))
        .opacity(pulse ? 0.7 : 1.0)
        .animation(
            .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
            value: pulse
        )
        .onAppear { pulse = true }
        .onDisappear { pulse = false }
    }

    private var formattedTime: String {
        let seconds = sessionManager.restTimerSeconds
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
