# claude-usage-bar

SwiftBar menu bar plugin that makes Claude Code's two limit numbers (5h session %,
7d week %) permanently visible, with detail in the dropdown:

```
⚡ 43% · 48%
---
Session (5h) ████░░░░░░ 43% · resets Sat 04:20
Week (7d)    █████░░░░░ 48% · resets Mon 16:00
Sonnet (7d)  ░░░░░░░░░░  0% · resets Mon 16:00
---
35,602,802 tokens today
in: 69,872 · out: 198,998 · cache read: 33,598,322 · cache write: 1,735,610
Cost today: $61.27
Latest session: 6,009,104 tokens
...
```

Limits come from the OAuth usage endpoint (plan-wide, all devices). Today/session
token stats come from local transcript JSONL under `~/.claude/projects/`, including
subagent transcripts, deduplicated once per `message.id`. Menu color: green < 50%,
yellow 50–79%, red ≥ 80%. On fetch failure the menu shows `⚡ —` with the last
cached values (suppressed once 24h or older); on 401/missing credentials it shows
`⚡ ⚠` with a sign-in hint.

Python 3.9 stdlib only — runs on macOS system Python, zero dependencies.

## Setup

```bash
brew install swiftbar
```

1. Launch SwiftBar and pick a plugin folder when prompted (e.g. `~/Documents/SwiftBar`).
2. Symlink the plugin into it — the `1m` in the symlink name is SwiftBar's refresh
   interval; the repo file keeps a valid module name so tests can import it:

   ```bash
   ln -s ~/Code/personal/claude-usage-bar/claude_usage.py \
         ~/Documents/SwiftBar/claude_usage.1m.py
   ```

3. **First run:** macOS will prompt for Keychain access to the
   `Claude Code-credentials` item. Click **Always Allow**, or SwiftBar's background
   refreshes will be blocked and the menu will show `⚡ ⚠` forever.

The token is read from the Keychain on each refresh and is never logged, cached,
or written to disk — only the usage response is cached
(`~/.cache/claude-usage-bar/last.json`).

## Cost estimate caveat

`Cost today` is an order-of-magnitude indicator, not billing:

- Cache writes blend 5-minute and 1-hour tiers but are priced at the 5m rate.
- Pricing is a static `PRICING` table in `claude_usage.py`, keyed by exact model id.
  Tokens from models missing from the table are excluded and the row gets a `≥`
  prefix (e.g. `≥ $4.20`) — if you see `≥` or `cost n/a (unpriced models)`, the
  table has gone stale and needs new entries.

## Verify

From the repo root, with the system Python (must be 3.9.x to prove the
`Z`-timestamp helper works):

```bash
/usr/bin/python3 -m unittest
```
