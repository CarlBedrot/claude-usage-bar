import Foundation

/// Parse ISO 8601 accepting both 'Z' (with optional fractional seconds) and
/// '+00:00' offsets. Returns nil on failure (the Python contract raises, but
/// callers here treat unparseable as "no date").
public func parseTimestamp(_ value: String) -> Date? {
    let withFractional = ISO8601DateFormatter()
    withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = withFractional.date(from: value) {
        return date
    }
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: value)
}

/// green < 50, yellow < 80, red otherwise. Matches the Python severity_color.
public func severityColor(_ utilization: Double) -> Severity {
    if utilization < 50 {
        return .green
    }
    if utilization < 80 {
        return .yellow
    }
    return .red
}

/// Parse the full usage response JSON into Limits. Returns nil if the payload
/// is not a JSON object. Individual partial/missing limits become nil fields.
public func parseLimits(json: String) -> Limits? {
    guard let data = json.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data),
          let dict = object as? [String: Any] else {
        return nil
    }
    return extractLimits(from: dict)
}

/// Build Limits from an already-parsed top-level dictionary.
public func extractLimits(from dict: [String: Any]) -> Limits {
    Limits(
        fiveHour: parseLimitObject(dict["five_hour"]),
        sevenDay: parseLimitObject(dict["seven_day"]),
        sevenDaySonnet: parseLimitObject(dict["seven_day_sonnet"])
    )
}

/// Return nil for null/partial/malformed limit objects, else the parsed limit.
/// Booleans are rejected as utilization (matching the Python isinstance(bool) guard).
func parseLimitObject(_ raw: Any?) -> Limit? {
    guard let dict = raw as? [String: Any] else {
        return nil
    }
    guard let utilization = numericValue(dict["utilization"]),
          let resetsRaw = dict["resets_at"] as? String,
          let resetsAt = parseTimestamp(resetsRaw) else {
        return nil
    }
    return Limit(utilization: utilization, resetsAt: resetsAt)
}

/// Extract a Double from an NSNumber while rejecting booleans, mirroring the
/// Python `isinstance(value, bool)` rejection.
private func numericValue(_ raw: Any?) -> Double? {
    guard let number = raw as? NSNumber else {
        return nil
    }
    // NSNumber wrapping a Bool reports the __NSCFBoolean type.
    if CFGetTypeID(number) == CFBooleanGetTypeID() {
        return nil
    }
    return number.doubleValue
}

/// Extract an integer token count, rejecting booleans and non-integers.
func readTokenCount(_ usage: [String: Any], _ key: String) -> Int {
    guard let number = usage[key] as? NSNumber else {
        return 0
    }
    if CFGetTypeID(number) == CFBooleanGetTypeID() {
        return 0
    }
    // Reject non-integers (the Python guard is isinstance(value, int)).
    if number.doubleValue != number.doubleValue.rounded() {
        return 0
    }
    return number.intValue
}
