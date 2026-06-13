import Foundation

/// Token counts for a single message or aggregated bucket.
/// Mirrors the Python COUNT_KEYS = (input, output, cache_read, cache_write).
public struct Counts: Equatable {
    public var input: Int
    public var output: Int
    public var cacheRead: Int
    public var cacheWrite: Int

    public init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
    }

    public var total: Int {
        input + output + cacheRead + cacheWrite
    }

    public mutating func add(_ other: Counts) {
        input += other.input
        output += other.output
        cacheRead += other.cacheRead
        cacheWrite += other.cacheWrite
    }
}

public func zeroCounts() -> Counts {
    Counts()
}

/// Per-model token counts, keyed by the model id as it appears in transcripts.
public typealias PerModelCounts = [String: Counts]

/// A single usage limit from the OAuth usage endpoint.
public struct Limit: Equatable {
    public let utilization: Double
    public let resetsAt: Date

    public init(utilization: Double, resetsAt: Date) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }
}

/// The three limits the app surfaces. A nil field means the limit was
/// absent/partial/malformed in the response.
public struct Limits: Equatable {
    public let fiveHour: Limit?
    public let sevenDay: Limit?
    public let sevenDaySonnet: Limit?

    public init(fiveHour: Limit?, sevenDay: Limit?, sevenDaySonnet: Limit?) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.sevenDaySonnet = sevenDaySonnet
    }
}

/// Errors raised by the I/O seams.
public enum UsageError: Error, Equatable {
    case auth
    case fetch
}

/// Top-level state driving the menu bar title and popover.
public enum UsageState: Equatable {
    case ok(Limits)
    case fetchError
    case authError
}

/// One recently-active session: its token usage plus a human label (the working
/// directory, and branch when it helps tell two sessions apart).
public struct SessionSummary: Equatable, Identifiable {
    public let id: String          // transcript path — stable across refreshes
    public let label: String
    public let counts: Counts
    public let lastModified: Date

    public init(id: String, label: String, counts: Counts, lastModified: Date) {
        self.id = id
        self.label = label
        self.counts = counts
        self.lastModified = lastModified
    }
}
