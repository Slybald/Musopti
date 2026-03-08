import SwiftUI

struct MusoptiTheme {
    // MARK: - Colors
    static let accent = Color(hex: "00E5CC")
    static let warning = Color(hex: "FF6B35")
    static let valid = Color(hex: "34D399")
    static let invalid = warning
    static let cardBackground = Color(hex: "1C1C1E")
    static let surfaceBackground = Color.black
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: "8E8E93")
    static let textTertiary = Color(hex: "48484A")
    static let phaseA = Color(hex: "3B82F6")
    static let hold = Color(hex: "F59E0B")
    static let phaseB = Color(hex: "8B5CF6")
    static let idle = Color(hex: "6B7280")
    static let repComplete = valid

    // MARK: - Fonts
    static let repCounter = Font.system(size: 72, weight: .bold, design: .rounded)
    static let repCounterSmall = Font.system(size: 48, weight: .bold, design: .rounded)
    static let phaseLabel = Font.system(size: 17, weight: .semibold)
    static let sectionTitle = Font.system(size: 20, weight: .bold)
    static let bodyText = Font.system(size: 15, weight: .regular)
    static let caption = Font.system(size: 13, weight: .regular)
    static let timer = Font.system(size: 28, weight: .medium, design: .monospaced)

    // MARK: - Spacing
    static let cardCornerRadius: CGFloat = 16
    static let smallPadding: CGFloat = 8
    static let mediumPadding: CGFloat = 16
    static let largePadding: CGFloat = 24

    // MARK: - Helpers
    static func phaseColor(for phase: MotionPhase) -> Color {
        switch phase {
        case .idle: return idle
        case .phaseA: return phaseA
        case .hold: return hold
        case .phaseB: return phaseB
        case .repComplete: return repComplete
        case .repInvalid: return invalid
        }
    }
}

// MARK: - Color Hex Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
