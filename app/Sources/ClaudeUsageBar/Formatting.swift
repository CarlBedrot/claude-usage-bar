import Foundation
import UsageCore

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

/// Compact "time since last activity" for a session: "now", "5m ago", "2h ago".
func relativeAge(_ date: Date, now: Date = Date()) -> String {
    let seconds = max(0, now.timeIntervalSince(date))
    switch seconds {
    case ..<90:
        return "now"
    case ..<3_600:
        return "\(Int((seconds / 60).rounded()))m ago"
    case ..<86_400:
        return "\(Int((seconds / 3_600).rounded()))h ago"
    default:
        return "\(Int((seconds / 86_400).rounded()))d ago"
    }
}

/// Thousands-grouped integer, e.g. 1,234,567.
func grouped(_ value: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = ","
    return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
}

/// Abbreviate a token count so the breakdown fits the card width: 70K, 48.0M.
func compact(_ value: Int) -> String {
    let n = Double(value)
    switch value {
    case ..<1_000:
        return "\(value)"
    case ..<1_000_000:
        return String(format: "%.0fK", n / 1_000)
    case ..<1_000_000_000:
        return String(format: "%.1fM", n / 1_000_000)
    default:
        return String(format: "%.1fB", n / 1_000_000_000)
    }
}

/// One-line in/out/cache breakdown for a counts bucket, abbreviated to fit.
func breakdownLine(_ counts: Counts) -> String {
    "in \(compact(counts.input)) · out \(compact(counts.output))"
        + " · cache read \(compact(counts.cacheRead)) · write \(compact(counts.cacheWrite))"
}

func sumModelCounts(_ perModel: PerModelCounts) -> Counts {
    var totals = zeroCounts()
    for counts in perModel.values {
        totals.add(counts)
    }
    return totals
}

/// The two limits the app surfaces, in display order.
let limitLabels: [(keyPath: KeyPath<Limits, Limit?>, label: String)] = [
    (\Limits.fiveHour, "Session (5h)"),
    (\Limits.sevenDay, "Week (7d)"),
]
