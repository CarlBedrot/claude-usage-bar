import Foundation

public let usageURL = "https://api.anthropic.com/api/oauth/usage"
public let oauthBetaHeader = "oauth-2025-04-20"
public let keychainService = "Claude Code-credentials"
public let httpTimeoutSeconds: TimeInterval = 10

/// Default scan root and cache path matching the spec's production wiring.
public func defaultScanRoot() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude")
        .appendingPathComponent("projects")
}

public func defaultCachePath() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library")
        .appendingPathComponent("Caches")
        .appendingPathComponent("com.carlbedrot.claude-usage-bar")
        .appendingPathComponent("last.json")
}

/// Read the OAuth access token from the macOS Keychain via the `security` CLI.
/// Throws UsageError.auth if the item is missing or has an unexpected shape.
public func readToken() throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    process.arguments = ["find-generic-password", "-s", keychainService, "-w"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()

    do {
        try process.run()
    } catch {
        throw UsageError.auth
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        throw UsageError.auth
    }
    let raw = (String(data: data, encoding: .utf8) ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let jsonData = raw.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: jsonData),
          let dict = object as? [String: Any],
          let oauth = dict["claudeAiOauth"] as? [String: Any],
          let token = oauth["accessToken"] as? String,
          !token.isEmpty else {
        throw UsageError.auth
    }
    return token
}

/// GET the OAuth usage endpoint and return the raw JSON body as a String.
/// HTTP 401 → UsageError.auth; any other failure → UsageError.fetch.
public func fetchUsage(token: String) throws -> Limits {
    guard let url = URL(string: usageURL) else {
        throw UsageError.fetch
    }
    var request = URLRequest(url: url, timeoutInterval: httpTimeoutSeconds)
    request.httpMethod = "GET"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue(oauthBetaHeader, forHTTPHeaderField: "anthropic-beta")

    let semaphore = DispatchSemaphore(value: 0)
    var resultData: Data?
    var resultResponse: URLResponse?
    var resultError: Error?

    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        resultData = data
        resultResponse = response
        resultError = error
        semaphore.signal()
    }
    task.resume()
    semaphore.wait()

    if resultError != nil {
        throw UsageError.fetch
    }
    if let http = resultResponse as? HTTPURLResponse {
        if http.statusCode == 401 {
            throw UsageError.auth
        }
        if !(200...299).contains(http.statusCode) {
            throw UsageError.fetch
        }
    }
    guard let data = resultData,
          let object = try? JSONSerialization.jsonObject(with: data),
          let dict = object as? [String: Any] else {
        throw UsageError.fetch
    }
    return extractLimits(from: dict)
}
