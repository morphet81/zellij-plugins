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

# --- Helpers ----------------------------------------------------------------

# Get the focused tab's name with icon prefix stripped
get_focused_tab_name() {
    zellij action dump-layout 2>/dev/null \
        | grep -E 'tab.*focus=true' \
        | head -1 \
        | sed 's/.*name="\([^"]*\)".*/\1/' \
        | sed 's/^🟢 //;s/^🔵 //;s/^🟡 //'
}

# Aggregate state across panes that share the same original tab name
# Sets $overall to waiting|working|idle
aggregate_tab_state() {
    tab_orig="$1"
    overall="idle"
    for f in "$STATE_DIR"/pane-*.state; do
        [ -f "$f" ] || continue
        pane_id=$(basename "$f" | sed 's/^pane-//;s/\.state$//')
        pane_orig=$(cat "${STATE_DIR}/pane-${pane_id}.orig" 2>/dev/null)
        [ "$pane_orig" = "$tab_orig" ] || continue
        s=$(cat "$f" 2>/dev/null)
        case "$s" in
            waiting) overall="waiting" ;;
            working) [ "$overall" != "waiting" ] && overall="working" ;;
        esac
    done
}

# Convert state to icon
state_to_icon() {
    case "$1" in
        waiting) echo "${AI_TAB_WAITING_ICON:-🟡}" ;;
        working) echo "${AI_TAB_WORKING_ICON:-🔵}" ;;
        *)       echo "${AI_TAB_IDLE_ICON:-🟢}" ;;
    esac
}

# --- Locking (prevents concurrent rename-tab calls) ------------------------

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

# --- Cleanup ----------------------------------------------------------------

if [ "$STATE" = "cleanup" ]; then
    orig=$(cat "$ORIG_FILE" 2>/dev/null)
    rm -f "$STATE_FILE" "$ORIG_FILE" 2>/dev/null

    # Clean up orphaned state files from panes that no longer exist
    layout=$(zellij action dump-layout 2>/dev/null || true)
    for f in "$STATE_DIR"/pane-*.state; do
        [ -f "$f" ] || continue
        pane_id=$(basename "$f" | sed 's/^pane-//;s/\.state$//')
        if ! echo "$layout" | grep -q "id=${pane_id}[^0-9]"; then
            rm -f "$f" "${STATE_DIR}/pane-${pane_id}.orig" 2>/dev/null
        fi
    done

    # Check if any panes from the same tab are still active
    has_same_tab=false
    if [ -n "$orig" ]; then
        for f in "$STATE_DIR"/pane-*.orig; do
            [ -f "$f" ] || continue
            if [ "$(cat "$f" 2>/dev/null)" = "$orig" ]; then
                has_same_tab=true
                break
            fi
        done
    fi

    if [ "$has_same_tab" = true ]; then
        # Other panes in this tab still active; update icon for remaining state
        focused=$(get_focused_tab_name)
        if [ -n "$orig" ] && [ "$focused" = "$orig" ]; then
            aggregate_tab_state "$orig"
            icon=$(state_to_icon "$overall")
            zellij action rename-tab "${icon} ${orig}" 2>/dev/null
        fi
    else
        # Last pane in this tab — restore original name
        focused=$(get_focused_tab_name)
        if [ -n "$orig" ] && [ "$focused" = "$orig" ]; then
            zellij action rename-tab "$orig" 2>/dev/null
        else
            # Tab not focused; leave a restore marker for precmd to pick up
            if [ -n "$orig" ]; then
                printf '%s' "$orig" > "${STATE_DIR}/restore-pending" 2>/dev/null
            fi
        fi
    fi
    exit 0
fi

# --- State update -----------------------------------------------------------

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

# Only rename if our tab is the currently focused tab
# (zellij action rename-tab always targets the focused tab)
focused=$(get_focused_tab_name)
[ "$focused" = "$orig" ] || exit 0

# Aggregate across panes in the SAME tab only (matched by orig name)
aggregate_tab_state "$orig"
icon=$(state_to_icon "$overall")

zellij action rename-tab "${icon} ${orig}" 2>/dev/null
