#!/bin/bash
# Removes everything install.sh added. Logs in ~/.local/state and agent rules are kept.
set -u

DOMAIN="gui/$(id -u)"
for label in dev.mac-dev-janitor.daily-clean dev.mac-dev-janitor.resource-watchdog; do
    launchctl bootout "$DOMAIN/$label" 2>/dev/null && echo "unloaded $label"
    rm -f "$HOME/Library/LaunchAgents/$label.plist"
done
rm -f "$HOME/.local/bin/daily-clean" "$HOME/.local/bin/resource-watchdog"
rm -rf "$HOME/Applications/DailyClean.app"
echo "Removed. Also remove DailyClean from System Settings > Privacy & Security > Full Disk Access."
