#!/bin/bash
# Install Claude Usage Bar as a login item via a LaunchAgent, so it starts
# automatically at login. Run after ./build.sh has produced ClaudeUsageBar.app.
set -euo pipefail

LABEL="com.carlbedrot.claude-usage-bar"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$SCRIPT_DIR/ClaudeUsageBar.app/Contents/MacOS/ClaudeUsageBar"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

if [ ! -x "$BIN" ]; then
    echo "error: $BIN not found — run ./build.sh first" >&2
    exit 1
fi

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array><string>$BIN</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><false/>
    <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
PLISTEOF

# Reload: stop any running instance and the old agent, then load fresh.
pkill -x ClaudeUsageBar 2>/dev/null || true
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

echo "Installed and loaded: $PLIST"
echo "Claude Usage Bar will now start at login (and is running now)."
