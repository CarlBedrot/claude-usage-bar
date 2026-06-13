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

/// macOS system orange, used for cost rows.
let costColor = Color(red: 1.0, green: 0.624, blue: 0.039) // #FF9F0A

/// Reset time formatted as "Mon 14:30" in Europe/Copenhagen.
func formatResetTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.timeZone = copenhagenTimeZone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "EEE HH:mm"
    return formatter.string(from: date)
}

/// Thousands-grouped integer, e.g. 1,234,567.
func grouped(_ value: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = ","
    return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
}

/// One-line in/out/cache breakdown for a counts bucket.
func breakdownLine(_ counts: Counts) -> String {
    "in: \(grouped(counts.input)) · out: \(grouped(counts.output))"
        + " · cache read: \(grouped(counts.cacheRead))"
        + " · cache write: \(grouped(counts.cacheWrite))"
}

func sumModelCounts(_ perModel: PerModelCounts) -> Counts {
    var totals = zeroCounts()
    for counts in perModel.values {
        totals.add(counts)
    }
    return totals
}

/// The three limits in display order with their labels.
let limitLabels: [(keyPath: KeyPath<Limits, Limit?>, label: String)] = [
    (\Limits.fiveHour, "Session (5h)"),
    (\Limits.sevenDay, "Week (7d)"),
    (\Limits.sevenDaySonnet, "Sonnet (7d)"),
]
