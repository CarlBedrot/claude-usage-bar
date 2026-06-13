# claude-usage-bar

A tiny macOS menu bar app that shows your **Claude Code** usage at a glance — the
two limits that actually matter (5-hour session, 7-day week), plus today's token
totals. Clay-on-cream, in Claude's own palette, with a little Clawd mascot that
peeks in now and then.

The menu bar reads `⚡ 43% · 4%` (session · week), color-coded; click it for the
full card view.

> Two builds live here: the **native SwiftUI app** (`app/`, the nice one) and a
> zero-dependency **SwiftBar plugin** (`claude_usage.py`, a lightweight text-menu
> fallback). Pick one.

## What it shows

- **Session (5h)** and **Week (7d)** limit utilization with reset times, straight
  from Claude's OAuth usage endpoint (plan-wide, all devices).
- **Today** and **latest session** token totals (in / out / cache read / write),
  read from your local transcripts under `~/.claude/projects/`, deduplicated per
  message and including subagent transcripts.

Your token is read from the macOS Keychain (`Claude Code-credentials`) on each
refresh and is **never logged, cached, or written to disk**.

## Requirements

- macOS 13+
- [Claude Code](https://claude.com/claude-code) installed and logged in (the app
  reads its Keychain credential and transcripts)
- Xcode Command Line Tools, to build: `xcode-select --install`

## Install (native app)

```bash
git clone https://github.com/CarlBedrot/claude-usage-bar.git
cd claude-usage-bar/app
./build.sh                 # compiles + bundles ClaudeUsageBar.app (no Xcode needed)
open ClaudeUsageBar.app    # launches it into your menu bar
./install-login-item.sh    # optional: start automatically at login
```

**First run:** macOS prompts for Keychain access to `Claude Code-credentials` —
click **Always Allow**. Because the app is ad-hoc signed for local use, Gatekeeper
may block the first launch; right-click the app → **Open**, or run
`xattr -dr com.apple.quarantine ClaudeUsageBar.app`.

Run the data-layer tests with `cd app && swift run UsageCoreTests`.

## Install (SwiftBar plugin, lightweight alternative)

Python 3.9 stdlib only — no build step.

```bash
brew install swiftbar
ln -s "$PWD/claude_usage.py" ~/Documents/SwiftBar/claude_usage.1m.py
```

(`1m` is the refresh interval; adjust to taste.) Same Keychain "Always Allow" on
first run. Tests: `/usr/bin/python3 -m unittest`.

## Notes

- **Rate limits:** the usage endpoint is rate-limited; the app polls every 5 min
  and refreshes when you open the popover. A transient failure keeps showing the
  last good limits rather than blanking out.
- **No cost figure:** if you're on a flat plan (Pro/Max), tokens don't cost you
  per-use, so the app shows counts, not dollars.

## License

MIT — see [LICENSE](LICENSE).
