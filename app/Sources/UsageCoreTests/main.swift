import Foundation
import UsageCore

// Hand-rolled assertion harness. XCTest is unavailable without Xcode, so this
// executable prints PASS/FAIL per case and exits non-zero if any case fails.

var failures = 0
var ran = 0

func check(_ name: String, _ condition: Bool) {
    ran += 1
    if condition {
        print("PASS  \(name)")
    } else {
        failures += 1
        print("FAIL  \(name)")
    }
}

// --- Fixture helpers ---------------------------------------------------------

let fileManager = FileManager.default

func makeTempDir(_ label: String) -> URL {
    let base = fileManager.temporaryDirectory
        .appendingPathComponent("usagecore-tests-\(label)-\(UUID().uuidString)")
    try! fileManager.createDirectory(at: base, withIntermediateDirectories: true)
    return base
}

func writeFile(_ url: URL, _ lines: [String], mtime: Date? = nil) {
    try! fileManager.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let contents = lines.joined(separator: "\n") + "\n"
    try! contents.write(to: url, atomically: true, encoding: .utf8)
    if let mtime = mtime {
        try! fileManager.setAttributes([.modificationDate: mtime], ofItemAtPath: url.path)
    }
}

// A usage-bearing JSONL entry. omitTimestamp drops the timestamp field entirely.
func usageEntry(id: String, model: String, timestamp: Date?,
                input: Int = 0, output: Int = 0,
                cacheRead: Int = 0, cacheWrite: Int = 0) -> String {
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var fields: [String] = []
    if let ts = timestamp {
        fields.append("\"timestamp\":\"\(iso.string(from: ts))\"")
    }
    let usage = "\"usage\":{\"input_tokens\":\(input),\"output_tokens\":\(output),"
        + "\"cache_read_input_tokens\":\(cacheRead),"
        + "\"cache_creation_input_tokens\":\(cacheWrite)}"
    let message = "\"message\":{\"id\":\"\(id)\",\"model\":\"\(model)\",\(usage)}"
    fields.append(message)
    return "{" + fields.joined(separator: ",") + "}"
}

func total(_ counts: Counts) -> Int {
    counts.input + counts.output + counts.cacheRead + counts.cacheWrite
}

// Europe/Copenhagen calendar so "today" / "yesterday" match the scan timezone.
let cph = TimeZone(identifier: "Europe/Copenhagen")!
var cphCalendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = cph
    return c
}()

// A fixed "now": midday so adding/subtracting hours stays within the same days.
let now = cphCalendar.date(from: DateComponents(year: 2026, month: 6, day: 13, hour: 12, minute: 0))!
let todayNoon = now
let yesterdayNoon = cphCalendar.date(byAdding: .day, value: -1, to: now)!

// --- Test 1: timestamp_z_and_offset ------------------------------------------

do {
    let z = parseTimestamp("2026-06-12T22:49:48.413Z")
    let offset = parseTimestamp("2026-06-15T14:00:01+00:00")
    let expectedZ = 1781304588.413   // 2026-06-12T22:49:48.413Z epoch
    let expectedOffset = 1781532001.0 // 2026-06-15T14:00:01Z epoch
    let zOk = z != nil && abs(z!.timeIntervalSince1970 - expectedZ) < 0.01
    let offsetOk = offset != nil && abs(offset!.timeIntervalSince1970 - expectedOffset) < 0.01
    check("timestamp_z_and_offset", zOk && offsetOk)
}

// --- Test 2: severity_boundaries ---------------------------------------------

do {
    let ok = severityLevel(49.9) == .low
        && severityLevel(50.0) == .mid
        && severityLevel(79.9) == .mid
        && severityLevel(80.0) == .high
    check("severity_boundaries", ok)
}

// --- Test 3: dedup_message_id_across_files ------------------------------------

do {
    let root = makeTempDir("dedup")
    // File A: id "dup" three times, plus a unique id.
    writeFile(root.appendingPathComponent("proj/a.jsonl"), [
        usageEntry(id: "dup", model: "m", timestamp: todayNoon, input: 100),
        usageEntry(id: "dup", model: "m", timestamp: todayNoon, input: 100),
        usageEntry(id: "dup", model: "m", timestamp: todayNoon, input: 100),
        usageEntry(id: "unique", model: "m", timestamp: todayNoon, input: 5),
    ], mtime: now)
    // File B: the same "dup" id again.
    writeFile(root.appendingPathComponent("proj/b.jsonl"), [
        usageEntry(id: "dup", model: "m", timestamp: todayNoon, input: 100),
    ], mtime: now)
    let per = scanToday(root: root, now: now)
    let counts = per["m"] ?? zeroCounts()
    // dup counted once (100) + unique (5) = 105
    check("dedup_message_id_across_files", total(counts) == 105)
}

// --- Test 4: today_excludes_yesterday ----------------------------------------

do {
    let root = makeTempDir("today-excl")
    writeFile(root.appendingPathComponent("proj/s.jsonl"), [
        usageEntry(id: "y", model: "m", timestamp: yesterdayNoon, input: 999),
        usageEntry(id: "t", model: "m", timestamp: todayNoon, input: 7),
    ], mtime: now)
    let per = scanToday(root: root, now: now)
    check("today_excludes_yesterday", total(per["m"] ?? zeroCounts()) == 7)
}

// --- Test 5: today_includes_subagents ----------------------------------------

do {
    let root = makeTempDir("today-sub")
    writeFile(root.appendingPathComponent("proj/sess.jsonl"), [
        usageEntry(id: "main", model: "m", timestamp: todayNoon, input: 10),
    ], mtime: now)
    writeFile(root.appendingPathComponent("proj/sess/subagents/agent-x.jsonl"), [
        usageEntry(id: "sub", model: "m", timestamp: todayNoon, input: 3),
    ], mtime: now)
    let per = scanToday(root: root, now: now)
    check("today_includes_subagents", total(per["m"] ?? zeroCounts()) == 13)
}

// --- Test 6: today_excludes_old_mtime ----------------------------------------

do {
    let root = makeTempDir("today-mtime")
    let oldMtime = now.addingTimeInterval(-40 * 3600)
    writeFile(root.appendingPathComponent("proj/s.jsonl"), [
        usageEntry(id: "t", model: "m", timestamp: todayNoon, input: 50),
    ], mtime: oldMtime)
    let per = scanToday(root: root, now: now)
    check("today_excludes_old_mtime", per.isEmpty)
}

// --- Test 7: active_sessions_sum (concurrent sessions + subagents + window) ---

do {
    let root = makeTempDir("active-sum")
    let window: TimeInterval = 3 * 3600
    let recentA = now.addingTimeInterval(-1 * 3600)
    let recentB = now.addingTimeInterval(-2 * 3600)
    let old = now.addingTimeInterval(-5 * 3600)
    writeFile(root.appendingPathComponent("proj/a.jsonl"), [
        usageEntry(id: "a", model: "m", timestamp: recentA, input: 10),
    ], mtime: recentA)
    writeFile(root.appendingPathComponent("proj/a/subagents/sa.jsonl"), [
        usageEntry(id: "sa", model: "m", timestamp: recentA, input: 5),
    ], mtime: recentA)
    writeFile(root.appendingPathComponent("proj/b.jsonl"), [
        usageEntry(id: "b", model: "m", timestamp: recentB, input: 100),
    ], mtime: recentB)
    writeFile(root.appendingPathComponent("proj/b/subagents/sb.jsonl"), [
        usageEntry(id: "sb", model: "m", timestamp: recentB, input: 50),
    ], mtime: recentB)
    // Outside the window → excluded from both count and totals.
    writeFile(root.appendingPathComponent("proj/old.jsonl"), [
        usageEntry(id: "old", model: "m", timestamp: old, input: 9999),
    ], mtime: old)
    let active = scanActiveSessions(root: root, now: now, windowSeconds: window)
    // 2 active sessions, summed with their subagents: 10+5+100+50 = 165.
    check("active_sessions_sum", active.count == 2 && total(active.totals) == 165)
}

// --- Test 8: subagent_not_counted_as_session ---------------------------------

do {
    let root = makeTempDir("sub-not-session")
    let recent = now.addingTimeInterval(-1 * 3600)
    writeFile(root.appendingPathComponent("proj/main.jsonl"), [
        usageEntry(id: "main", model: "m", timestamp: recent, input: 20),
    ], mtime: recent)
    // An orphan subagent file (no parent session) must not be counted as a
    // session nor have its tokens included.
    writeFile(root.appendingPathComponent("proj/other/subagents/sub.jsonl"), [
        usageEntry(id: "sub", model: "m", timestamp: recent, input: 999),
    ], mtime: recent)
    let active = scanActiveSessions(root: root, now: now, windowSeconds: 3 * 3600)
    check("subagent_not_counted_as_session", active.count == 1 && total(active.totals) == 20)
}

// --- Test 9: entry_without_timestamp -----------------------------------------

do {
    let root = makeTempDir("no-ts")
    writeFile(root.appendingPathComponent("proj/s.jsonl"), [
        usageEntry(id: "dated", model: "m", timestamp: todayNoon, input: 4),
        usageEntry(id: "nodate", model: "m", timestamp: nil, input: 6),
    ], mtime: now)
    let todayCounts = total(scanToday(root: root, now: now)["m"] ?? zeroCounts())
    let active = scanActiveSessions(root: root, now: now, windowSeconds: 3 * 3600)
    // Today counts only the dated entry; an active session counts both.
    check("entry_without_timestamp", todayCounts == 4 && active.count == 1 && total(active.totals) == 10)
}

// --- Test 10: truncated_line_skipped -----------------------------------------

do {
    let root = makeTempDir("truncated")
    writeFile(root.appendingPathComponent("proj/s.jsonl"), [
        usageEntry(id: "valid", model: "m", timestamp: todayNoon, input: 8),
        "{\"message\":{\"id\":\"broke\",\"model\":\"m\",\"usage\":{\"input_to",
    ], mtime: now)
    let per = scanToday(root: root, now: now)
    check("truncated_line_skipped", total(per["m"] ?? zeroCounts()) == 8)
}

// --- Test 11: vanished_file_skipped ------------------------------------------

do {
    let root = makeTempDir("vanished")
    let good = root.appendingPathComponent("proj/good.jsonl")
    let gone = root.appendingPathComponent("proj/gone.jsonl")
    writeFile(good, [usageEntry(id: "g", model: "m", timestamp: todayNoon, input: 11)], mtime: now)
    writeFile(gone, [usageEntry(id: "x", model: "m", timestamp: todayNoon, input: 11)], mtime: now)
    // readEntries must tolerate a path that no longer exists.
    let empty = readEntries(path: gone.deletingLastPathComponent().appendingPathComponent("does-not-exist.jsonl"))
    let per = scanToday(root: root, now: now)
    check("vanished_file_skipped", empty.isEmpty && total(per["m"] ?? zeroCounts()) == 22)
}

// --- Test 12: cost_known_model -----------------------------------------------

do {
    // 1,000,000 output tokens at synthetic $15.0/MTok output = $15.00
    var counts = zeroCounts()
    counts.output = 1_000_000
    let pricing = Pricing(input: 0, output: 15.0, cacheRead: 0, cacheWrite: 0)
    let per: PerModelCounts = ["synthetic": counts]
    let row = costRow(perModel: per, pricingTable: ["synthetic": pricing])
    check("cost_known_model", row == "Cost today: $15.00")
}

// --- Test 13: cost_unknown_geq -----------------------------------------------

do {
    var priced = zeroCounts(); priced.output = 1_000_000
    var unpriced = zeroCounts(); unpriced.input = 500
    let pricing = Pricing(input: 0, output: 15.0, cacheRead: 0, cacheWrite: 0)
    let per: PerModelCounts = ["synthetic": priced, "mystery": unpriced]
    let row = costRow(perModel: per, pricingTable: ["synthetic": pricing])
    check("cost_unknown_geq", row == "Cost today: ≥ $15.00")
}

// --- Test 14: cost_all_unpriced ----------------------------------------------

do {
    var unpriced = zeroCounts(); unpriced.input = 500
    let per: PerModelCounts = ["mystery": unpriced]
    let row = costRow(perModel: per, pricingTable: [:])
    check("cost_all_unpriced", row == "cost n/a (unpriced models)")
}

// --- Test 15: cache_roundtrip_and_stale --------------------------------------

do {
    let dir = makeTempDir("cache-fresh")
    let cachePath = dir.appendingPathComponent("last.json")
    let response = "{\"five_hour\":{\"utilization\":43.0,\"resets_at\":\"2026-06-13T18:00:00Z\"},"
        + "\"seven_day\":{\"utilization\":48.0,\"resets_at\":\"2026-06-20T18:00:00Z\"}}"
    // Write at -12m: fresh
    let freshNow = now
    try! writeCache(cachePath: cachePath, responseJSON: response, now: freshNow.addingTimeInterval(-12 * 60))
    let fresh = readCache(cachePath: cachePath, now: freshNow)
    var freshOk = false
    if case .fresh(let limits, _) = fresh {
        freshOk = limits.fiveHour?.utilization == 43.0
    }
    // Write at -25h: stale
    let staleDir = makeTempDir("cache-stale")
    let stalePath = staleDir.appendingPathComponent("last.json")
    try! writeCache(cachePath: stalePath, responseJSON: response, now: freshNow.addingTimeInterval(-25 * 3600))
    let stale = readCache(cachePath: stalePath, now: freshNow)
    var staleOk = false
    if case .stale = stale { staleOk = true }
    check("cache_roundtrip_and_stale", freshOk && staleOk)
}

// --- Test 16: cache_excludes_token -------------------------------------------

do {
    let dir = makeTempDir("cache-token")
    let cachePath = dir.appendingPathComponent("last.json")
    let response = "{\"five_hour\":{\"utilization\":43.0,\"resets_at\":\"2026-06-13T18:00:00Z\"}}"
    try! writeCache(cachePath: cachePath, responseJSON: response, now: now)
    let onDisk = (try? String(contentsOf: cachePath, encoding: .utf8)) ?? ""
    check("cache_excludes_token", !onDisk.contains("SECRET_TOKEN_VALUE") && !onDisk.contains("accessToken"))
}

// --- Test 17: menu_line_ok ---------------------------------------------------

do {
    let limits = Limits(
        fiveHour: Limit(utilization: 43.0, resetsAt: now),
        sevenDay: Limit(utilization: 48.0, resetsAt: now),
        sevenDaySonnet: nil)
    let line = menuLine(state: .ok(limits))
    check("menu_line_ok", line == "⚡ 43% · 48%")
}

// --- Test 18: menu_line_nil_and_errors ---------------------------------------

do {
    let nilSlot = Limits(
        fiveHour: nil,
        sevenDay: Limit(utilization: 30.0, resetsAt: now),
        sevenDaySonnet: nil)
    let nilLine = menuLine(state: .ok(nilSlot))
    let fetchLine = menuLine(state: .fetchError)
    let authLine = menuLine(state: .authError)
    let over = Limits(
        fiveHour: Limit(utilization: 105.0, resetsAt: now),
        sevenDay: Limit(utilization: 30.0, resetsAt: now),
        sevenDaySonnet: nil)
    let overLine = menuLine(state: .ok(over))
    let ok = nilLine == "⚡ – · 30%"
        && fetchLine == "⚡ —"
        && authLine == "⚡ ⚠"
        && overLine == "⚡ 105% · 30%"
    check("menu_line_nil_and_errors", ok)
}

// --- Test 19: limits_parse_partial_nil ---------------------------------------

do {
    // five_hour is complete; seven_day is missing resets_at → nil.
    let json = "{\"five_hour\":{\"utilization\":43.0,\"resets_at\":\"2026-06-13T18:00:00Z\"},"
        + "\"seven_day\":{\"utilization\":48.0}}"
    let limits = parseLimits(json: json)
    let ok = limits != nil
        && limits!.fiveHour != nil
        && limits!.sevenDay == nil
    check("limits_parse_partial_nil", ok)
}

// --- Summary -----------------------------------------------------------------

print("\n\(ran - failures)/\(ran) passed")
if failures > 0 {
    print("\(failures) FAILED")
    exit(1)
}
print("ALL PASS")
exit(0)
