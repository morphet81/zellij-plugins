#!/bin/sh
# Claude Tab Monitor - Hook script
# Called by Claude Code hooks to report state to the Zellij plugin
# Usage: hook.sh <state>
# States: working, waiting, idle, exit

# Bail silently if not in Zellij
[ -z "$ZELLIJ" ] && exit 0
[ -z "$ZELLIJ_PANE_ID" ] && exit 0

state="${1:?Usage: hook.sh <working|waiting|idle|exit>}"

zellij pipe --name claude-status -- "{\"pane_id\":\"$ZELLIJ_PANE_ID\",\"state\":\"$state\"}"
