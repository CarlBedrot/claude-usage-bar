import Foundation
import SwiftUI
import UsageCore

/// Map a UsageCore Severity to a SwiftUI Color.
func color(for severity: Severity) -> Color {
    switch severity {
    case .green:
        return .green
    case .yellow:
        return .yellow
    case .red:
        return .red
    case .gray:
        return .gray
    }
}

/// Reset time in the /usage panel style, in Europe/Copenhagen:
///   today  -> "Resets 2:10pm (Europe/Copenhagen)"
///   later  -> "Resets Jun 15 at 4pm (Europe/Copenhagen)"
func formatReset(_ date: Date, now: Date = Date()) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = copenhagenTimeZone

    let time = DateFormatter()
    time.timeZone = copenhagenTimeZone
    time.locale = Locale(identifier: "en_US_POSIX")
    // Drop ":00" minutes ("4pm"), keep them otherwise ("2:10pm").
    time.dateFormat = calendar.component(.minute, from: date) == 0 ? "ha" : "h:mma"
    let timeText = time.string(from: date).lowercased()

    if calendar.isDate(date, inSameDayAs: now) {
        return "Resets \(timeText) (Europe/Copenhagen)"
    }
    let day = DateFormatter()
    day.timeZone = copenhagenTimeZone
    day.locale = Locale(identifier: "en_US_POSIX")
    day.dateFormat = "MMM d"
    return "Resets \(day.string(from: date)) at \(timeText) (Europe/Copenhagen)"
}

/// The two limits the app surfaces, in display order.
let limitLabels: [(keyPath: KeyPath<Limits, Limit?>, label: String)] = [
    (\Limits.fiveHour, "Session (5h)"),
    (\Limits.sevenDay, "Week (7d)"),
]
