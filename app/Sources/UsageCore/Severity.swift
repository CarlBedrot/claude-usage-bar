import Foundation

/// How close a limit is to its ceiling. Names are color-agnostic — the palette
/// layer decides the actual hue (currently clay / burnt / brick). `.unknown`
/// means there's no data to grade.
public enum Severity: Equatable {
    case low
    case mid
    case high
    case unknown
}

/// Grade a utilization percentage: low < 50, mid < 80, high otherwise.
/// Matches the Python `severity_color` thresholds.
public func severityLevel(_ utilization: Double) -> Severity {
    if utilization < 50 {
        return .low
    }
    if utilization < 80 {
        return .mid
    }
    return .high
}
