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
LOCK_DIR="${STATE_DIR}/hook.lock"

# --- Locking (prevents concurrent rename-tab calls) ----------------------

# Clean stale locks older than 5 seconds
if [ -d "$LOCK_DIR" ]; then
    lock_age=$(find "$LOCK_DIR" -maxdepth 0 -mmin +0.08 2>/dev/null)
    if [ -n "$lock_age" ]; then
        rmdir "$LOCK_DIR" 2>/dev/null
    fi
fi

# Acquire lock (mkdir is atomic)
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    exit 0
fi

# Release lock on exit
trap 'rmdir "$LOCK_DIR" 2>/dev/null' EXIT

# --- Cleanup --------------------------------------------------------------

if [ "$STATE" = "cleanup" ]; then
    orig=$(cat "$ORIG_FILE" 2>/dev/null)
    rm -f "$STATE_FILE" "$ORIG_FILE" 2>/dev/null
    # Restore tab name if no active monitors remain
    if ! ls "$STATE_DIR"/pane-*.state >/dev/null 2>&1; then
        if [ -n "$orig" ]; then
            zellij action rename-tab "$orig" 2>/dev/null
        else
            zellij action undo-rename-tab 2>/dev/null
        fi
    fi
    exit 0
fi

# --- State update ---------------------------------------------------------

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

# Read original tab name — bail if empty (don't rename to just an icon)
orig=""
[ -f "$ORIG_FILE" ] && orig=$(cat "$ORIG_FILE" 2>/dev/null)
[ -z "$orig" ] && exit 0

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
