import SwiftUI

struct PhaseIndicatorView: View {
    @Environment(SessionManager.self) private var sessionManager

    var body: some View {
        Text(phaseLabel)
            .font(MusoptiTheme.phaseLabel)
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(MusoptiTheme.phaseColor(for: sessionManager.currentPhase))
            .clipShape(Capsule())
            .animation(.easeInOut(duration: 0.3), value: sessionManager.currentPhase)
    }

    private var phaseLabel: String {
        let raw = sessionManager.currentPhase.rawValue
        if raw == "idle" { return "Idle" }
        return raw
    }
}
