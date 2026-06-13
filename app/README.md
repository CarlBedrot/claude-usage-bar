# Claude Usage Bar — native macOS app

A native SwiftUI menu-bar agent showing Claude Code session/week limit
utilization, today's deduplicated transcript token counts with estimated cost,
and latest-session stats. This supersedes the SwiftBar Python plugin at the repo
root (which is kept as a zero-dependency fallback) by rendering a proper
card-based popover instead of plain menu text.

The data layer (`UsageCore`) is a 1:1 Swift port of `../claude_usage.py` — same
OAuth fetch, Keychain read, transcript scanning, dedup, cost rules, and cache
behavior.

## Requirements

- macOS 13+ (built/tested on 14.5, arm64)
- Swift 5.10 via Command Line Tools — **no full Xcode required**

## Build

```sh
cd app
./build.sh
```

This runs `swift build -c release`, assembles `ClaudeUsageBar.app` by hand, and
ad-hoc codesigns it. The bundle path is printed at the end.

## Run

```sh
open ClaudeUsageBar.app
```

The app has no Dock icon (it's a menu-bar agent, `LSUIElement`). Look for the
`⚡` item in the menu bar. Click it to open the popover; use the popover's
**Quit** button to stop it.

### First run — Keychain

On its first background fetch the app reads the Claude Code OAuth token from the
Keychain (`security find-generic-password -s "Claude Code-credentials"`). macOS
will prompt for access — choose **Always Allow** so it can refresh silently every
60 seconds. The token is only used in-memory for the API call; it is never logged
or written to the cache file.

If you are not signed in, the menu bar shows `⚡ ⚠` and the popover says
"Sign in to Claude Code (run claude, then /login)".

## Add as a login item

To start it automatically:

System Settings → General → Login Items → **+** → select `ClaudeUsageBar.app`.

(Because the app is ad-hoc signed for local use, macOS may ask you to confirm.
If Gatekeeper blocks the first launch, right-click the app → **Open**.)

## Tests

The data layer has a hand-rolled assertion runner (XCTest is unavailable without
Xcode):

```sh
cd app
swift run UsageCoreTests
```

It prints `PASS`/`FAIL` per case and exits non-zero on any failure.

## Relationship to the Python plugin

The Python SwiftBar plugin (`../claude_usage.py`) stays in the repo as a
lightweight fallback. Once you're running the native app you can disable the
SwiftBar widget — they show the same numbers.
