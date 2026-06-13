import Foundation
import SwiftUI
import UsageCore

/// Everything the popover renders: just the two usage limits (or an error).
struct UsageSnapshot {
    var state: UsageState

    static let empty = UsageSnapshot(state: .fetchError)
}

/// Fetches the usage limits in the background and publishes them on the main actor.
@MainActor
final class UsageModel: ObservableObject {
    @Published private(set) var snapshot = UsageSnapshot.empty
    @Published private(set) var isRefreshing = false

    private let fetcher: (String) throws -> Limits
    private let keychainReader: () throws -> String

    /// Called whenever a fresh snapshot is published, so the status item title
    /// can be re-rendered.
    var onUpdate: ((UsageSnapshot) -> Void)?

    init(fetcher: @escaping (String) throws -> Limits = fetchUsage,
         keychainReader: @escaping () throws -> String = readToken) {
        self.fetcher = fetcher
        self.keychainReader = keychainReader
    }

    /// Refresh off the main thread, then publish on the main actor.
    func refresh() {
        if isRefreshing {
            return
        }
        isRefreshing = true

        let fetcher = self.fetcher
        let keychainReader = self.keychainReader

        Task.detached(priority: .userInitiated) {
            let snapshot = UsageModel.buildSnapshot(fetcher: fetcher, keychainReader: keychainReader)
            await MainActor.run {
                self.snapshot = snapshot
                self.isRefreshing = false
                self.onUpdate?(snapshot)
            }
        }
    }

    /// Pure assembly of a snapshot — no UI, runs off the main thread.
    nonisolated static func buildSnapshot(
        fetcher: (String) throws -> Limits,
        keychainReader: () throws -> String) -> UsageSnapshot {

        do {
            let token = try keychainReader()
            return UsageSnapshot(state: .ok(try fetcher(token)))
        } catch UsageError.auth {
            return UsageSnapshot(state: .authError)
        } catch {
            return UsageSnapshot(state: .fetchError)
        }
    }
}
