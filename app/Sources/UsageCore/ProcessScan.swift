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

/// Parse `ps -axo pid=,tty=,comm=` output into the pids of *interactive*
/// `claude` sessions: command basename exactly "claude" AND attached to a real
/// terminal. This excludes the desktop app ("Claude", "Claude Helper"), node
/// child processes, and headless/background `claude` invocations (a `claude -p`
/// or subagent has tty "??", so it isn't a session you're sitting in).
public func interactiveClaudePids(fromPsOutput output: String) -> [String] {
    var pids: [String] = []
    for line in output.split(separator: "\n") {
        let columns = line.split(separator: " ", omittingEmptySubsequences: true)
        guard columns.count >= 3 else {
            continue
        }
        let tty = String(columns[1])
        let comm = columns[2...].joined(separator: " ")
        guard tty != "??", !tty.isEmpty,
              URL(fileURLWithPath: comm).lastPathComponent == "claude" else {
            continue
        }
        pids.append(String(columns[0]))
    }
    return pids
}

/// Working directories of running interactive `claude` sessions — one entry per
/// process, so the count is the number of sessions you have open. This is the
/// authoritative signal; file timestamps can't see a session that's idle at the
/// prompt (it writes nothing).
///
/// Returns nil if process inspection itself fails (caller falls back to the
/// mtime heuristic); an empty array means no sessions are running.
public func detectRunningClaudeCwds() -> [String]? {
    guard let listing = runCommand("/bin/ps", ["-axo", "pid=,tty=,comm="]) else {
        return nil
    }

    let pids = interactiveClaudePids(fromPsOutput: listing)

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
