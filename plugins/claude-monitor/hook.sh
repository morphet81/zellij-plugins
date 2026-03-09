#!/bin/sh
# Claude Tab Monitor - Hook script
# Called by Claude Code hooks to report state to the Zellij plugin
# Usage: hook.sh <state>
# States: working, waiting, idle, exit

# Bail silently if not in Zellij
[ -z "$ZELLIJ" ] && exit 0
[ -z "$ZELLIJ_PANE_ID" ] && exit 0

state="${1:?Usage: hook.sh <working|waiting|idle|exit>}"

PLUGIN_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_URL="file:${PLUGIN_DIR}/claude-tab-monitor.wasm"

# Run in background: --plugin auto-launches the plugin if not running.
# Redirect output to /dev/null to avoid blocking Claude hooks.
zellij pipe --plugin "$PLUGIN_URL" --name claude-status -- "{\"pane_id\":\"$ZELLIJ_PANE_ID\",\"state\":\"$state\"}" >/dev/null 2>&1 &
