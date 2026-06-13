import Foundation
import SwiftUI
import UsageCore

/// Everything the popover renders: the two limits, today's tokens, and the
/// combined usage of currently-active sessions.
struct UsageSnapshot {
    var state: UsageState
    var todayByModel: PerModelCounts
    var activeSessions: ActiveSessions

    static let empty = UsageSnapshot(
        state: .fetchError, todayByModel: [:],
        activeSessions: ActiveSessions(count: 0, totals: zeroCounts()))
}

/// Outcome of a limits fetch, before it's reconciled with the last-known value.
private enum LimitsOutcome {
    case ok(Limits)
    case auth
    case failed
}

/// Fetches limits + scans token usage in the background, publishes on the main actor.
@MainActor
final class UsageModel: ObservableObject {
    @Published private(set) var snapshot = UsageSnapshot.empty
    @Published private(set) var isRefreshing = false

    /// Last successfully fetched limits, kept so a transient rate-limit (429)
    /// doesn't blank the cards — we keep showing the most recent good values.
    private var lastLimits: Limits?
    private var lastAttempt: Date?

    private let scanRoot: URL
    private let fetcher: (String) throws -> Limits
    private let keychainReader: () throws -> String

    var onUpdate: ((UsageSnapshot) -> Void)?

    init(scanRoot: URL = defaultScanRoot(),
         fetcher: @escaping (String) throws -> Limits = fetchUsage,
         keychainReader: @escaping () throws -> String = readToken) {
        self.scanRoot = scanRoot
        self.fetcher = fetcher
        self.keychainReader = keychainReader
    }

    /// Refresh off the main thread. `force` bypasses the min-interval throttle
    /// (used by the manual Refresh button); auto-refreshes coalesce.
    func refresh(force: Bool = false) {
        if isRefreshing {
            return
        }
        if !force, let last = lastAttempt, Date().timeIntervalSince(last) < 30 {
            return
        }
        isRefreshing = true
        lastAttempt = Date()

        let scanRoot = self.scanRoot
        let fetcher = self.fetcher
        let keychainReader = self.keychainReader

        Task.detached(priority: .userInitiated) {
            let (outcome, today, active) = UsageModel.gather(
                scanRoot: scanRoot, fetcher: fetcher,
                keychainReader: keychainReader, now: Date())
            await MainActor.run {
                self.apply(outcome: outcome, today: today, active: active)
                self.isRefreshing = false
            }
        }
    }

    private func apply(outcome: LimitsOutcome, today: PerModelCounts, active: ActiveSessions) {
        let state: UsageState
        switch outcome {
        case .ok(let limits):
            lastLimits = limits
            state = .ok(limits)
        case .auth:
            state = .authError
        case .failed:
            // Keep the last good limits on a transient failure; only show the
            // error card if we've never had a successful fetch.
            state = lastLimits.map { .ok($0) } ?? .fetchError
        }
        snapshot = UsageSnapshot(state: state, todayByModel: today, activeSessions: active)
        onUpdate?(snapshot)
    }

    /// Pure gather: scan tokens (always) and attempt the limits fetch.
    nonisolated private static func gather(
        scanRoot: URL,
        fetcher: (String) throws -> Limits,
        keychainReader: () throws -> String,
        now: Date) -> (LimitsOutcome, PerModelCounts, ActiveSessions) {

        let today = scanToday(root: scanRoot, now: now)
        let active = scanActiveSessions(root: scanRoot, now: now)

        let outcome: LimitsOutcome
        do {
            let token = try keychainReader()
            outcome = .ok(try fetcher(token))
        } catch UsageError.auth {
            outcome = .auth
        } catch {
            outcome = .failed
        }
        return (outcome, today, active)
    }
}
