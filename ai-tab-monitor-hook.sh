#!/bin/sh
# ai-tab-monitor-hook.sh — Claude Code hook for Zellij tab state updates
#
# Called by Claude Code hooks to update the Zellij tab icon.
# Receives the desired state as $1: working|waiting|idle|cleanup
#
# Requires ZELLIJ, ZELLIJ_SESSION_NAME, and ZELLIJ_PANE_ID env vars.

[ -z "$ZELLIJ" ] && exit 0
[ -z "$ZELLIJ_PANE_ID" ] && exit 0

STATE="${1:-idle}"
STATE_DIR="/tmp/ai-tab-monitor-${ZELLIJ_SESSION_NAME}"
STATE_FILE="${STATE_DIR}/pane-${ZELLIJ_PANE_ID}.state"
ORIG_FILE="${STATE_DIR}/pane-${ZELLIJ_PANE_ID}.orig"

if [ "$STATE" = "cleanup" ]; then
    rm -f "$STATE_FILE" 2>/dev/null
    # Restore tab name if no active monitors remain
    if ! ls "$STATE_DIR"/pane-*.state >/dev/null 2>&1; then
        zellij action undo-rename-tab 2>/dev/null
    fi
    exit 0
fi

case "$STATE" in
    working|waiting|idle) ;;
    *) exit 0 ;;
esac

# Skip rename if state unchanged
if [ -f "$STATE_FILE" ] && [ "$(cat "$STATE_FILE" 2>/dev/null)" = "$STATE" ]; then
    exit 0
fi

mkdir -p "$STATE_DIR" 2>/dev/null
printf '%s' "$STATE" > "$STATE_FILE"

# Read original tab name
orig=""
[ -f "$ORIG_FILE" ] && orig=$(cat "$ORIG_FILE" 2>/dev/null)

# Aggregate across all panes: waiting > working > idle
overall="idle"
for f in "$STATE_DIR"/pane-*.state; do
    [ -f "$f" ] || continue
    s=$(cat "$f" 2>/dev/null)
    case "$s" in
        waiting) overall="waiting" ;;
        working) [ "$overall" != "waiting" ] && overall="working" ;;
    esac
done

case "$overall" in
    waiting) icon="${AI_TAB_WAITING_ICON:-🟡}" ;;
    working) icon="${AI_TAB_WORKING_ICON:-🔵}" ;;
    *)       icon="${AI_TAB_IDLE_ICON:-🟢}" ;;
esac

zellij action rename-tab "${icon} ${orig}" 2>/dev/null
