import Foundation

/// Run a command and capture its stdout, or nil if it fails to launch.
/// stderr is discarded; output is expected to be small (process listings).
func runCommand(_ launchPath: String, _ arguments: [String]) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    let outPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
    } catch {
        return nil
    }
    let data = outPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(data: data, encoding: .utf8)
}

/// Working directories of running `claude` CLI processes — one entry per
/// process, so the count is the number of concurrent sessions. This is the
/// authoritative "sessions I have open" signal; file timestamps can't see a
/// session that's idle at the prompt (it writes nothing).
///
/// Returns nil if process inspection itself fails (caller falls back to the
/// mtime heuristic); an empty array means no sessions are running.
public func detectRunningClaudeCwds() -> [String]? {
    guard let listing = runCommand("/bin/ps", ["-axo", "pid=,comm="]) else {
        return nil
    }

    // Keep processes whose command basename is exactly "claude" — this excludes
    // the desktop app ("Claude", "Claude Helper") and the node child processes.
    var pids: [String] = []
    for line in listing.split(separator: "\n") {
        let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else {
            continue
        }
        let comm = parts[1].trimmingCharacters(in: .whitespaces)
        if URL(fileURLWithPath: comm).lastPathComponent == "claude" {
            pids.append(String(parts[0]))
        }
    }

    var cwds: [String] = []
    for pid in pids {
        guard let output = runCommand("/usr/sbin/lsof", ["-a", "-p", pid, "-d", "cwd", "-Fn"]) else {
            continue
        }
        for line in output.split(separator: "\n") where line.hasPrefix("n") {
            cwds.append(String(line.dropFirst()))
            break
        }
    }

    // Found sessions but couldn't read any cwd → signal failure so the caller
    // falls back to the mtime heuristic rather than reporting zero sessions.
    if !pids.isEmpty && cwds.isEmpty {
        return nil
    }
    return cwds
}
