import Foundation

extension TimeInterval {
    var formatted: String {
        let totalSeconds = Int(self)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        } else if minutes > 0 {
            return seconds > 0 ? "\(minutes)m \(seconds)s" : "\(minutes)m"
        } else {
            return "\(seconds)s"
        }
    }
}

extension Int {
    var formattedFileSize: String {
        let bytes = Double(self)
        if bytes < 1024 {
            return "\(self) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", bytes / 1024)
        } else if bytes < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB", bytes / (1024 * 1024))
        } else {
            return String(format: "%.1f GB", bytes / (1024 * 1024 * 1024))
        }
    }
}

extension Date {
    var relativeFormatted: String {
        let calendar = Calendar.current

        if calendar.isDateInToday(self) {
            return "Today"
        } else if calendar.isDateInYesterday(self) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            let daysDiff = calendar.dateComponents([.day], from: self, to: .now).day ?? 0
            formatter.dateFormat = daysDiff < 7 ? "EEEE" : "MMM d"
            return formatter.string(from: self)
        }
    }

    var shortRelativeTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: self, relativeTo: .now)
    }
}

extension Double {
    func formattedWeight(unit: String) -> String {
        if unit == "lbs" {
            let lbs = self * 2.20462
            return String(format: "%.0f lbs", lbs)
        } else {
            return String(format: "%.0f kg", self)
        }
    }

    func formattedWeight(unit: WeightUnit) -> String {
        formattedWeight(unit: unit.rawValue)
    }
}
