#!/bin/sh
# ai-tab-monitor-hook.sh — Claude Code hook for Zellij tab state updates
#
# Called by Claude Code hooks to update the Zellij tab icon.
# Receives the desired state as $1: working|waiting|idle|cleanup
#
# Requires ZELLIJ, ZELLIJ_SESSION_NAME, and ZELLIJ_PANE_ID env vars.
#
# Debug: set AI_TAB_DEBUG=1 to log to /tmp/ai-tab-monitor-debug.log

[ -z "$ZELLIJ" ] && exit 0
[ -z "$ZELLIJ_PANE_ID" ] && exit 0

STATE="${1:-idle}"
STATE_DIR="/tmp/ai-tab-monitor-${ZELLIJ_SESSION_NAME}"
STATE_FILE="${STATE_DIR}/pane-${ZELLIJ_PANE_ID}.state"
ORIG_FILE="${STATE_DIR}/pane-${ZELLIJ_PANE_ID}.orig"
LOCK_DIR="${STATE_DIR}/hook.lock"
DEBUG_LOG="/tmp/ai-tab-monitor-debug.log"

# --- Debug ------------------------------------------------------------------

debug() {
    [ "${AI_TAB_DEBUG:-0}" = "1" ] || return 0
    printf '[%s] pane=%s state=%s | %s\n' \
        "$(date '+%H:%M:%S')" "$ZELLIJ_PANE_ID" "$STATE" "$*" >> "$DEBUG_LOG"
}

# --- Helpers ----------------------------------------------------------------

# Get the tab name for a specific pane ID from dump-layout.
# Falls back to the focused tab if pane not found.
get_pane_tab_name() {
    target_pane="$1"
    layout=$(zellij action dump-layout 2>/dev/null) || return

    # awk: track the most recent "tab" line's name attribute,
    # print it when we find a line containing our pane id.
    name=$(printf '%s' "$layout" | awk -v pid="$target_pane" '
        /^[[:space:]]*(tab|fake_tab) / {
            s = $0
            if (match(s, /name="[^"]*"/)) {
                current_tab = substr(s, RSTART + 6, RLENGTH - 7)
            }
        }
        {
            pattern = "id=" pid
            idx = index($0, pattern)
            if (idx > 0) {
                # Verify next char after the id digits is not a digit (exact match)
                rest = substr($0, idx + length(pattern), 1)
                if (rest == "" || rest !~ /[0-9]/) {
                    print current_tab
                    exit
                }
            }
        }
    ')

    debug "get_pane_tab_name($target_pane) raw='$name'"

    # Strip known icon prefixes
    name=$(printf '%s' "$name" | sed 's/^🟢 //;s/^🔵 //;s/^🟡 //')

    printf '%s' "$name"
}

# Get the focused tab's name with icon prefix stripped
get_focused_tab_name() {
    name=$(zellij action dump-layout 2>/dev/null \
        | grep -E '(tab|fake_tab).*focus=true' \
        | head -1 \
        | sed 's/.*name="\([^"]*\)".*/\1/' \
        | sed 's/^🟢 //;s/^🔵 //;s/^🟡 //')
    debug "get_focused_tab_name() = '$name'"
    printf '%s' "$name"
}

# Aggregate state across panes that share the same original tab name.
# Sets $overall to waiting|working|idle
aggregate_tab_state() {
    tab_orig="$1"
    overall="idle"
    for f in "$STATE_DIR"/pane-*.state; do
        [ -f "$f" ] || continue
        p_id=$(basename "$f" | sed 's/^pane-//;s/\.state$//')
        p_orig=$(cat "${STATE_DIR}/pane-${p_id}.orig" 2>/dev/null)
        [ "$p_orig" = "$tab_orig" ] || continue
        s=$(cat "$f" 2>/dev/null)
        case "$s" in
            waiting) overall="waiting" ;;
            working) [ "$overall" != "waiting" ] && overall="working" ;;
        esac
    done
    debug "aggregate_tab_state('$tab_orig') = $overall"
}

# Convert state to icon
state_to_icon() {
    case "$1" in
        waiting) printf '%s' "${AI_TAB_WAITING_ICON:-🟡}" ;;
        working) printf '%s' "${AI_TAB_WORKING_ICON:-🔵}" ;;
        *)       printf '%s' "${AI_TAB_IDLE_ICON:-🟢}" ;;
    esac
}

# --- Locking (prevents concurrent rename-tab calls) ------------------------

# Acquire lock with retry — hooks fire nearly simultaneously and the old
# "fail immediately" approach silently dropped events.
lock_acquired=false
for _i in 1 2 3 4 5 6 7 8 9 10; do
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        lock_acquired=true
        break
    fi
    sleep 0.05
done

# If still locked, try clearing a stale lock (older than ~5 seconds)
if [ "$lock_acquired" = false ] && [ -d "$LOCK_DIR" ]; then
    lock_age=$(find "$LOCK_DIR" -maxdepth 0 -mmin +0.08 2>/dev/null)
    if [ -n "$lock_age" ]; then
        rmdir "$LOCK_DIR" 2>/dev/null
        mkdir "$LOCK_DIR" 2>/dev/null && lock_acquired=true
    fi
fi

if [ "$lock_acquired" = false ]; then
    debug "LOCK FAILED — exiting"
    exit 0
fi

# Release lock on exit
trap 'rmdir "$LOCK_DIR" 2>/dev/null' EXIT

debug "--- hook invoked ---"

# --- Cleanup ----------------------------------------------------------------

if [ "$STATE" = "cleanup" ]; then
    # If the wrapper shell is still alive, this is a mid-session event
    # (e.g. /clear fires SessionEnd) — treat as idle, not a real exit.
    PID_FILE="${STATE_DIR}/pane-${ZELLIJ_PANE_ID}.pid"
    if [ -f "$PID_FILE" ]; then
        wrapper_pid=$(cat "$PID_FILE" 2>/dev/null)
        if [ -n "$wrapper_pid" ] && kill -0 "$wrapper_pid" 2>/dev/null; then
            debug "cleanup → idle (wrapper pid $wrapper_pid still alive)"
            STATE="idle"
        fi
    fi
fi

if [ "$STATE" = "cleanup" ]; then
    orig=$(cat "$ORIG_FILE" 2>/dev/null)
    debug "cleanup: orig='$orig'"
    rm -f "$STATE_FILE" "$ORIG_FILE" 2>/dev/null

    # Clean up orphaned state files from panes that no longer exist
    layout=$(zellij action dump-layout 2>/dev/null || true)
    for f in "$STATE_DIR"/pane-*.state; do
        [ -f "$f" ] || continue
        p_id=$(basename "$f" | sed 's/^pane-//;s/\.state$//')
        if ! printf '%s' "$layout" | grep -q "id=${p_id}[^0-9]"; then
            debug "cleanup: removing orphaned pane-${p_id}"
            rm -f "$f" "${STATE_DIR}/pane-${p_id}.orig" 2>/dev/null
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
            debug "cleanup: other panes active, rename to '${icon} ${orig}'"
            zellij action rename-tab "${icon} ${orig}" 2>/dev/null
        fi
    else
        # Last pane in this tab — restore original name
        focused=$(get_focused_tab_name)
        if [ -n "$orig" ] && [ "$focused" = "$orig" ]; then
            debug "cleanup: restoring tab name to '$orig'"
            zellij action rename-tab "$orig" 2>/dev/null
        else
            # Tab not focused; leave a restore marker for precmd to pick up
            if [ -n "$orig" ]; then
                debug "cleanup: tab not focused, writing restore-pending"
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

# Guard: "idle" must not override "waiting". The Stop hook fires right after
# Notification(permission_prompt), and its "idle" would overwrite the yellow
# pill. A waiting-lock file lets us skip exactly one spurious "idle".
WAITING_LOCK="${STATE_DIR}/pane-${ZELLIJ_PANE_ID}.waiting-lock"

if [ "$STATE" = "waiting" ]; then
    touch "$WAITING_LOCK" 2>/dev/null
elif [ "$STATE" = "idle" ] && [ -f "$WAITING_LOCK" ]; then
    rm -f "$WAITING_LOCK" 2>/dev/null
    debug "idle blocked by waiting-lock"
    exit 0
else
    rm -f "$WAITING_LOCK" 2>/dev/null
fi

# Skip rename if state unchanged
if [ -f "$STATE_FILE" ] && [ "$(cat "$STATE_FILE" 2>/dev/null)" = "$STATE" ]; then
    debug "state unchanged ($STATE), skipping"
    exit 0
fi

mkdir -p "$STATE_DIR" 2>/dev/null
printf '%s' "$STATE" > "$STATE_FILE"

# Read original tab name — bail if empty (don't rename to just an icon)
orig=""
[ -f "$ORIG_FILE" ] && orig=$(cat "$ORIG_FILE" 2>/dev/null)
if [ -z "$orig" ]; then
    debug "orig empty, skipping rename"
    exit 0
fi

# Only rename if our pane's tab is the currently focused tab.
# zellij action rename-tab always targets the focused tab, so renaming
# when a different tab is focused would contaminate that tab's name.
our_tab=$(get_pane_tab_name "$ZELLIJ_PANE_ID")
focused=$(get_focused_tab_name)

debug "our_tab='$our_tab' focused='$focused' orig='$orig'"

if [ "$focused" != "$orig" ]; then
    debug "focused tab ('$focused') != orig ('$orig'), skipping rename"
    exit 0
fi

# Aggregate across panes in the SAME tab only (matched by orig name)
aggregate_tab_state "$orig"
icon=$(state_to_icon "$overall")

debug "rename-tab '${icon} ${orig}'"
zellij action rename-tab "${icon} ${orig}" 2>/dev/null
