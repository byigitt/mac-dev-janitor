#!/bin/bash
# Installs mac-dev-janitor for the current user.
#
#   ./install.sh [--hour N] [--no-clean] [--no-watchdog] [--agent-rules] [--no-load]
#
#   --hour N        hour of day for the daily cleanup (default 20)
#   --no-clean      skip the daily cleanup job
#   --no-watchdog   skip the resource watchdog
#   --agent-rules   append agent-rules.md to ~/.claude/CLAUDE.md and ~/.codex/AGENTS.md
#   --no-load       write files only, do not load the LaunchAgents
set -euo pipefail

cd "$(dirname "$0")"

HOUR=20
CLEAN=1
WATCHDOG=1
AGENT_RULES=0
LOAD=1
while (($#)); do
    case "$1" in
        --hour) HOUR="$2"; shift ;;
        --no-clean) CLEAN=0 ;;
        --no-watchdog) WATCHDOG=0 ;;
        --agent-rules) AGENT_RULES=1 ;;
        --no-load) LOAD=0 ;;
        -h | --help) sed -n '2,11p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
[[ "$HOUR" =~ ^([01]?[0-9]|2[0-3])$ ]] || { echo "--hour must be 0-23" >&2; exit 2; }

BIN_DIR="$HOME/.local/bin"
STATE_DIR="$HOME/.local/state"
AGENTS_DIR="$HOME/Library/LaunchAgents"
APP="$HOME/Applications/DailyClean.app"
CLEAN_LABEL="dev.mac-dev-janitor.daily-clean"
WATCHDOG_LABEL="dev.mac-dev-janitor.resource-watchdog"
DOMAIN="gui/$(id -u)"

mkdir -p "$BIN_DIR" "$STATE_DIR" "$AGENTS_DIR"

load() {
    local label="$1"
    ((LOAD)) || return 0
    launchctl bootout "$DOMAIN/$label" 2>/dev/null || true
    launchctl bootstrap "$DOMAIN" "$AGENTS_DIR/$label.plist"
    echo "loaded $label"
}

if ((CLEAN)); then
    command -v mo >/dev/null || echo "warning: Mole (mo) not found; install it with: brew install mole" >&2
    install -m 755 bin/daily-clean "$BIN_DIR/daily-clean"

    # A tiny app wrapper so Full Disk Access can be granted to this job alone
    # (repos under ~/Desktop or ~/Documents are TCC-protected for launchd jobs).
    mkdir -p "$(dirname "$APP")"
    rm -rf "$APP"
    osacompile -o "$APP" -e "do shell script \"/bin/bash '$BIN_DIR/daily-clean' >> '$STATE_DIR/daily-clean.log' 2>&1\""
    plutil -replace CFBundleIdentifier -string "$CLEAN_LABEL" "$APP/Contents/Info.plist"
    plutil -insert LSUIElement -bool true "$APP/Contents/Info.plist"
    codesign --force --deep -s - "$APP" 2>/dev/null

    # No LowPriorityIO / Background ProcessType: IO throttling makes Mole's per-path
    # timeouts fire, and Mole then skips the deletion.
    cat >"$AGENTS_DIR/$CLEAN_LABEL.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$CLEAN_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$APP/Contents/MacOS/applet</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>$HOUR</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
</dict>
</plist>
PLIST
    plutil -lint -s "$AGENTS_DIR/$CLEAN_LABEL.plist"
    load "$CLEAN_LABEL"
fi

if ((WATCHDOG)); then
    install -m 755 bin/resource-watchdog "$BIN_DIR/resource-watchdog"
    cat >"$AGENTS_DIR/$WATCHDOG_LABEL.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$WATCHDOG_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>$BIN_DIR/resource-watchdog</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>StandardOutPath</key>
    <string>$STATE_DIR/resource-watchdog.err</string>
    <key>StandardErrorPath</key>
    <string>$STATE_DIR/resource-watchdog.err</string>
</dict>
</plist>
PLIST
    plutil -lint -s "$AGENTS_DIR/$WATCHDOG_LABEL.plist"
    load "$WATCHDOG_LABEL"
fi

if ((AGENT_RULES)); then
    for f in "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md"; do
        mkdir -p "$(dirname "$f")"
        if grep -qs 'resource-watchdog-kills.txt' "$f"; then
            echo "agent rules already in $f"
        else
            [[ -s "$f" ]] && echo >>"$f"
            cat agent-rules.md >>"$f"
            echo "appended agent rules to $f"
        fi
    done
fi

echo
echo "Done."
if ((CLEAN)); then
    echo "Next: grant Full Disk Access to $APP"
    echo "  System Settings > Privacy & Security > Full Disk Access > + > Cmd+Shift+G > paste the path"
    echo "Preview the cleanup with: $BIN_DIR/daily-clean --dry-run"
fi
