import Foundation
import SwiftUI
import UsageCore

/// Snapshot of everything the popover renders, published on the main thread.
struct UsageSnapshot {
    var state: UsageState
    var cache: CacheState
    var todayByModel: PerModelCounts
    var sessionTotals: Counts

    static let empty = UsageSnapshot(
        state: .fetchError,
        cache: .missing,
        todayByModel: [:],
        sessionTotals: zeroCounts())
}

/// Drives a background refresh and publishes results to the UI on the main actor.
@MainActor
final class UsageModel: ObservableObject {
    @Published private(set) var snapshot = UsageSnapshot.empty
    @Published private(set) var isRefreshing = false

    private let scanRoot: URL
    private let cachePath: URL
    private let fetcher: (String) throws -> Limits
    private let keychainReader: () throws -> String

    /// Called whenever a fresh snapshot is published, so the status item title
    /// can be re-rendered.
    var onUpdate: ((UsageSnapshot) -> Void)?

    init(scanRoot: URL = defaultScanRoot(),
         cachePath: URL = defaultCachePath(),
         fetcher: @escaping (String) throws -> Limits = fetchUsage,
         keychainReader: @escaping () throws -> String = readToken) {
        self.scanRoot = scanRoot
        self.cachePath = cachePath
        self.fetcher = fetcher
        self.keychainReader = keychainReader
    }

    /// Refresh off the main thread, then publish on the main actor.
    func refresh() {
        if isRefreshing {
            return
        }
        isRefreshing = true

        let scanRoot = self.scanRoot
        let cachePath = self.cachePath
        let fetcher = self.fetcher
        let keychainReader = self.keychainReader

        Task.detached(priority: .userInitiated) {
            let snapshot = UsageModel.buildSnapshot(
                scanRoot: scanRoot,
                cachePath: cachePath,
                fetcher: fetcher,
                keychainReader: keychainReader,
                now: Date())
            await MainActor.run {
                self.snapshot = snapshot
                self.isRefreshing = false
                self.onUpdate?(snapshot)
            }
        }
    }

    /// Pure assembly of a snapshot — no UI, runs off the main thread.
    nonisolated static func buildSnapshot(
        scanRoot: URL,
        cachePath: URL,
        fetcher: (String) throws -> Limits,
        keychainReader: () throws -> String,
        now: Date) -> UsageSnapshot {

        let todayByModel = scanToday(root: scanRoot, now: now)
        let sessionTotals = scanLatestSession(root: scanRoot)

        var state: UsageState = .fetchError
        do {
            let token = try keychainReader()
            let limits = try fetcher(token)
            state = .ok(limits)
            // Re-serialize the limits we got so the cache round-trips. The token
            // is never part of this payload.
            if let responseJSON = serializeLimits(limits, now: now) {
                try? writeCache(cachePath: cachePath, responseJSON: responseJSON, now: now)
            }
        } catch UsageError.auth {
            state = .authError
        } catch {
            state = .fetchError
        }

        var cache: CacheState = .missing
        if case .ok = state {
            // No cache panel needed on success.
        } else {
            cache = readCache(cachePath: cachePath, now: now)
        }

        return UsageSnapshot(
            state: state,
            cache: cache,
            todayByModel: todayByModel,
            sessionTotals: sessionTotals)
    }
}

/// Serialize Limits back into the on-the-wire JSON shape for caching.
private func serializeLimits(_ limits: Limits, now: Date) -> String? {
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    func object(_ limit: Limit?) -> [String: Any]? {
        guard let limit = limit else {
            return nil
        }
        return ["utilization": limit.utilization, "resets_at": iso.string(from: limit.resetsAt)]
    }

    var response: [String: Any] = [:]
    if let five = object(limits.fiveHour) { response["five_hour"] = five }
    if let seven = object(limits.sevenDay) { response["seven_day"] = seven }
    if let sonnet = object(limits.sevenDaySonnet) { response["seven_day_sonnet"] = sonnet }

    guard let data = try? JSONSerialization.data(withJSONObject: response),
          let string = String(data: data, encoding: .utf8) else {
        return nil
    }
    return string
}
