import Foundation

/// The top-level state driving the menu bar title and popover.
public enum UsageState: Equatable {
    case ok(Limits)
    case fetchError
    case authError
}

func roundPercent(_ utilization: Double) -> Int {
    Int(utilization.rounded())
}

/// Render one limit slot: "43%" or "–" for nil. >100 is left unclamped.
func renderSlot(_ limit: Limit?) -> String {
    guard let limit = limit else {
        return "–"
    }
    return "\(roundPercent(limit.utilization))%"
}

/// Worst severity across the two menu limits, gray when neither is present.
public func menuSeverity(_ limits: Limits) -> Severity {
    let utilizations = [limits.fiveHour, limits.sevenDay]
        .compactMap { $0?.utilization }
    guard let worst = utilizations.max() else {
        return .gray
    }
    return severityColor(worst)
}

/// The menu bar title text.
/// ok: "⚡ {5h}% · {7d}%"; fetch error: "⚡ —"; auth error: "⚡ ⚠".
public func menuLine(state: UsageState) -> String {
    switch state {
    case .authError:
        return "⚡ ⚠"
    case .fetchError:
        return "⚡ —"
    case .ok(let limits):
        return "⚡ \(renderSlot(limits.fiveHour)) · \(renderSlot(limits.sevenDay))"
    }
}
