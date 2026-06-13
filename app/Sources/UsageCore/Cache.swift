import Foundation

let cacheMaxAgeSeconds: TimeInterval = 24 * 3600

/// Result of reading the on-disk cache.
public enum CacheState: Equatable {
    case fresh(limits: Limits, ageSeconds: TimeInterval)
    case stale
    case missing
}

/// Persist the last good usage response with its fetch timestamp. The token is
/// never part of the response, so it is never written.
public func writeCache(cachePath: URL, responseJSON: String, now: Date) throws {
    try FileManager.default.createDirectory(
        at: cachePath.deletingLastPathComponent(), withIntermediateDirectories: true)
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    // Store the raw response verbatim so readCache can re-parse it with the
    // same logic as a live fetch.
    let responseObject = try JSONSerialization.jsonObject(
        with: Data(responseJSON.utf8))
    let payload: [String: Any] = [
        "fetched_at": iso.string(from: now),
        "response": responseObject,
    ]
    let data = try JSONSerialization.data(withJSONObject: payload)
    try data.write(to: cachePath)
}

/// Read cached limits. Returns .stale when ≥ 24h old, .missing on any error.
public func readCache(cachePath: URL, now: Date) -> CacheState {
    guard let data = try? Data(contentsOf: cachePath),
          let object = try? JSONSerialization.jsonObject(with: data),
          let payload = object as? [String: Any],
          let fetchedRaw = payload["fetched_at"] as? String,
          let fetchedAt = parseTimestamp(fetchedRaw),
          let response = payload["response"] as? [String: Any] else {
        return .missing
    }
    let ageSeconds = now.timeIntervalSince(fetchedAt)
    if ageSeconds >= cacheMaxAgeSeconds {
        return .stale
    }
    return .fresh(limits: extractLimits(from: response), ageSeconds: ageSeconds)
}

/// Human-readable cache age: "12m" under an hour, else "2h".
public func formatAge(_ ageSeconds: TimeInterval) -> String {
    let minutes = Int(ageSeconds / 60)
    if minutes < 60 {
        return "\(minutes)m"
    }
    return "\(minutes / 60)h"
}
