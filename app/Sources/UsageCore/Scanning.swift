import Foundation

let subagentDirName = "subagents"
let todayScanWindowSeconds: TimeInterval = 36 * 3600
/// A session counts as "active" if its transcript was written this recently.
/// Kept tight so it reflects sessions running *now*, not every transcript
/// touched in the last few hours (mtime catches idle/resumed sessions too).
public let activeSessionWindowSeconds: TimeInterval = 15 * 60
public let copenhagenTimeZone = TimeZone(identifier: "Europe/Copenhagen")!

/// A usage-bearing entry's extracted fields.
struct MessageUsage {
    let messageId: String
    let model: String
    let counts: Counts
}

/// Read JSONL entries; skip unparseable lines; empty list if file vanished.
/// Each entry is the parsed top-level JSON object for one line.
public func readEntries(path: URL) -> [[String: Any]] {
    guard let contents = try? String(contentsOf: path, encoding: .utf8) else {
        return []
    }
    var entries: [[String: Any]] = []
    for line in contents.split(separator: "\n", omittingEmptySubsequences: true) {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else {
            continue
        }
        entries.append(dict)
    }
    return entries
}

/// Return the (id, model, counts) for usage-bearing entries, else nil.
func extractMessageUsage(_ entry: [String: Any]) -> MessageUsage? {
    guard let message = entry["message"] as? [String: Any],
          let usage = message["usage"] as? [String: Any],
          let messageId = message["id"] as? String else {
        return nil
    }
    let model = (message["model"] as? String) ?? "unknown"
    let counts = Counts(
        input: readTokenCount(usage, "input_tokens"),
        output: readTokenCount(usage, "output_tokens"),
        cacheRead: readTokenCount(usage, "cache_read_input_tokens"),
        cacheWrite: readTokenCount(usage, "cache_creation_input_tokens")
    )
    return MessageUsage(messageId: messageId, model: model, counts: counts)
}

/// The entry's calendar day in Europe/Copenhagen, or nil if no/unparseable timestamp.
func entryDate(_ entry: [String: Any]) -> Date? {
    guard let raw = entry["timestamp"] as? String,
          let parsed = parseTimestamp(raw) else {
        return nil
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = copenhagenTimeZone
    return calendar.startOfDay(for: parsed)
}

func fileModificationDate(_ path: URL) -> Date {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
          let date = attrs[.modificationDate] as? Date else {
        return Date(timeIntervalSince1970: 0)
    }
    return date
}

/// All *.jsonl files under root, sorted by path (deterministic like the Python glob).
func jsonlFiles(in root: URL) -> [URL] {
    let manager = FileManager.default
    guard let enumerator = manager.enumerator(
        at: root,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]) else {
        return []
    }
    var results: [URL] = []
    for case let url as URL in enumerator where url.pathExtension == "jsonl" {
        results.append(url)
    }
    return results.sorted { $0.path < $1.path }
}

/// Per-model token counts for entries dated today (Europe/Copenhagen).
/// Recursive scan (subagents included) over files modified within 36h,
/// counted once per message.id across all files.
public func scanToday(root: URL, now: Date) -> PerModelCounts {
    var perModel: PerModelCounts = [:]
    var seenIds: Set<String> = []

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = copenhagenTimeZone
    let today = calendar.startOfDay(for: now)
    let cutoff = now.addingTimeInterval(-todayScanWindowSeconds)

    for path in jsonlFiles(in: root) {
        if fileModificationDate(path) < cutoff {
            continue
        }
        for entry in readEntries(path: path) {
            accumulateTodayEntry(entry, into: &perModel, seenIds: &seenIds, today: today)
        }
    }
    return perModel
}

/// Dedup happens BEFORE the date check (matching the Python order): a duplicate
/// id seen on any day suppresses later occurrences, then only today's count.
func accumulateTodayEntry(_ entry: [String: Any], into perModel: inout PerModelCounts,
                          seenIds: inout Set<String>, today: Date) {
    guard let usage = extractMessageUsage(entry) else {
        return
    }
    if seenIds.contains(usage.messageId) {
        return
    }
    seenIds.insert(usage.messageId)
    if entryDate(entry) != today {
        return
    }
    perModel[usage.model, default: zeroCounts()].add(usage.counts)
}

/// Subagent transcripts owned by a session: <parent>/<stem>/subagents/*.jsonl.
func subagentFiles(for session: URL) -> [URL] {
    let stem = session.deletingPathExtension().lastPathComponent
    let subagentDir = session.deletingLastPathComponent()
        .appendingPathComponent(stem)
        .appendingPathComponent(subagentDirName)
    return jsonlFiles(in: subagentDir)
}

func relativePathComponents(of url: URL, under root: URL) -> [String] {
    let rootComponents = root.standardizedFileURL.pathComponents
    let urlComponents = url.standardizedFileURL.pathComponents
    guard urlComponents.count > rootComponents.count,
          Array(urlComponents.prefix(rootComponents.count)) == rootComponents else {
        return urlComponents
    }
    return Array(urlComponents.dropFirst(rootComponents.count))
}

/// Non-subagent transcripts modified within the active window — one per session.
func activeSessionTranscripts(root: URL, now: Date, windowSeconds: TimeInterval) -> [URL] {
    let cutoff = now.addingTimeInterval(-windowSeconds)
    return jsonlFiles(in: root).filter { url in
        !relativePathComponents(of: url, under: root).contains(subagentDirName)
            && fileModificationDate(url) >= cutoff
    }
}

/// One summary per recently-active session — its tokens (session + its own
/// subagents, deduped by message.id within the session) and a folder/branch
/// label — newest first. Concurrent sessions are all included, not just one.
public func scanActiveSessions(root: URL, now: Date,
                               windowSeconds: TimeInterval = activeSessionWindowSeconds) -> [SessionSummary] {
    var summaries: [SessionSummary] = []
    for session in activeSessionTranscripts(root: root, now: now, windowSeconds: windowSeconds) {
        var totals = zeroCounts()
        var seenIds: Set<String> = []
        var cwd: String?
        var branch: String?
        for path in [session] + subagentFiles(for: session) {
            for entry in readEntries(path: path) {
                if cwd == nil { cwd = entry["cwd"] as? String }
                if branch == nil { branch = entry["gitBranch"] as? String }
                guard let usage = extractMessageUsage(entry), !seenIds.contains(usage.messageId) else {
                    continue
                }
                seenIds.insert(usage.messageId)
                totals.add(usage.counts)
            }
        }
        summaries.append(SessionSummary(
            id: session.path,
            label: sessionLabel(cwd: cwd, branch: branch, transcript: session),
            counts: totals,
            lastModified: fileModificationDate(session)))
    }
    return summaries.sorted { $0.lastModified > $1.lastModified }
}

/// Folder name from the session's cwd, with the branch appended when it adds
/// signal (not main/HEAD). Falls back to a short transcript id if cwd is absent.
func sessionLabel(cwd: String?, branch: String?, transcript: URL) -> String {
    guard let cwd = cwd, !cwd.isEmpty else {
        return String(transcript.deletingPathExtension().lastPathComponent.prefix(8))
    }
    let folder = URL(fileURLWithPath: cwd).lastPathComponent
    if let branch = branch, !branch.isEmpty, branch != "HEAD", branch != "main", branch != "master" {
        return "\(folder) · \(branch)"
    }
    return folder
}
