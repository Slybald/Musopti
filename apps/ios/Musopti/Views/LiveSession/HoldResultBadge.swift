import SwiftUI

struct HoldResultBadge: View {
    @Environment(SessionManager.self) private var sessionManager

    var body: some View {
        if let result = sessionManager.holdResult {
            HStack(spacing: MusoptiTheme.smallPadding) {
                image(for: result)
                    .font(.system(size: 18, weight: .semibold))
                text(for: result)
                    .font(MusoptiTheme.bodyText)
            }
            .foregroundStyle(color(for: result))
            .padding(MusoptiTheme.smallPadding)
            .background(MusoptiTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: MusoptiTheme.cardCornerRadius))
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
            .animation(.easeInOut(duration: 0.3), value: sessionManager.holdResult)
        }
    }

    private func durationText(_ ms: UInt32) -> String {
        String(format: "%.1fs", Double(ms) / 1000.0)
    }

    private func image(for result: HoldResult) -> Image {
        switch result {
        case .valid:
            Image(systemName: "checkmark.circle.fill")
        case .tooShort, .tooLong:
            Image(systemName: "exclamationmark.triangle.fill")
        }
    }

    private func text(for result: HoldResult) -> Text {
        switch result {
        case .valid(let ms):
            Text("Hold: \(durationText(ms)) \u{2713}")
        case .tooShort(let ms):
            Text("Hold: \(durationText(ms)) — too short")
        case .tooLong(let ms):
            Text("Hold: \(durationText(ms)) — too long")
        }
    }

    private func color(for result: HoldResult) -> Color {
        switch result {
        case .valid: MusoptiTheme.valid
        case .tooShort, .tooLong: MusoptiTheme.warning
        }
    }
}
