#!/usr/bin/env zsh
# ai-tab-monitor.zsh — Zellij tab indicator for AI coding agent sessions
#
# Monitors Claude Code and Cursor Agent sessions running in Zellij,
# showing their status as a colored icon prepended to the tab name.
#
#   🟢 <tab name>  — idle (ready for a new query)
#   🔵 <tab name>  — working (processing/generating)
#   🟡 <tab name>  — waiting for user approval (permission prompt)
#   (original)     — restored when all sessions exit
#
# Claude Code: Uses native hooks (event-driven, instant, no polling).
# Cursor Agent: Falls back to periodic screen content monitoring.
#
# Source this in your .zshrc:
#   source /path/to/ai-tab-monitor.zsh
#
# Configuration (optional env vars):
#   AI_TAB_POLL_INTERVAL  — seconds between screen checks for Cursor Agent (default: 1)
#   AI_TAB_WAITING_ICON   — icon for waiting state (default: 🟡)
#   AI_TAB_WORKING_ICON   — icon for working state (default: 🔵)
#   AI_TAB_IDLE_ICON      — icon for idle state (default: 🟢)

# Resolve hook script path relative to this file
typeset -g __ATM_HOOK="${0:A:h}/ai-tab-monitor-hook.sh"

# --- Shared helpers --------------------------------------------------------

__atm_get_tab_name() {
    local raw
    raw=$(zellij action dump-layout 2>/dev/null \
        | grep -E 'tab.*focus=true' \
        | head -1 \
        | sed 's/.*name="\([^"]*\)".*/\1/')
    # Strip known icon prefixes (handles multi-byte emoji correctly)
    if [[ "$raw" == (🟢|🔵|🟡)\ * ]]; then
        raw="${raw#* }"
    fi
    echo "${raw}"
}

__atm_capture_orig_name() {
    local state_dir="/tmp/ai-tab-monitor-${ZELLIJ_SESSION_NAME}"
    local orig_file="${state_dir}/pane-${ZELLIJ_PANE_ID}.orig"
    if [[ ! -f "$orig_file" ]]; then
        mkdir -p "$state_dir" 2>/dev/null
        local name
        name=$(__atm_get_tab_name)
        # Retry once if empty (dump-layout can transiently fail)
        if [[ -z "$name" ]]; then
            sleep 0.2
            name=$(__atm_get_tab_name)
        fi
        # Only write if we got a non-empty name
        if [[ -n "$name" ]]; then
            printf '%s' "$name" > "$orig_file"
        fi
    fi
}

# --- Precmd: restore stale icons when switching to a tab -------------------

__atm_precmd_refresh() {
    [[ -n "$ZELLIJ" ]] || return
    local state_dir="/tmp/ai-tab-monitor-${ZELLIJ_SESSION_NAME}"

    # Check for pending restore (cleanup couldn't rename because tab wasn't focused)
    if [[ -f "${state_dir}/restore-pending" ]]; then
        local pending_name
        pending_name=$(<"${state_dir}/restore-pending")
        local current_tab
        current_tab=$(__atm_get_tab_name)
        if [[ "$pending_name" == "$current_tab" ]]; then
            zellij action rename-tab "$pending_name" 2>/dev/null
            rm -f "${state_dir}/restore-pending" 2>/dev/null
        fi
    fi
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd __atm_precmd_refresh

# --- Claude Code (hook-driven, no polling) ---------------------------------

claude() {
    if [[ -n "$ZELLIJ" ]] && [[ -n "$ZELLIJ_PANE_ID" ]]; then
        local state_dir="/tmp/ai-tab-monitor-${ZELLIJ_SESSION_NAME}"
        __atm_capture_orig_name
        # Write PID so the hook can distinguish mid-session events (e.g. /clear)
        # from real exits: if this shell is still alive, cleanup becomes idle.
        mkdir -p "$state_dir" 2>/dev/null
        printf '%s' "$$" > "${state_dir}/pane-${ZELLIJ_PANE_ID}.pid"
        bash "$__ATM_HOOK" idle

        command claude "$@"
        local _exit=$?

        # Remove PID before safety-net cleanup so the hook knows it's a real exit
        rm -f "${state_dir}/pane-${ZELLIJ_PANE_ID}.pid" 2>/dev/null
        bash "$__ATM_HOOK" cleanup 2>/dev/null
        return $_exit
    else
        command claude "$@"
    fi
}

# --- Cursor Agent (screen-scraping fallback) -------------------------------

__atm_is_waiting() {
    local content=$1
    [[ "$content" == *'(Y)es'* ]] && return 0
    [[ "$content" == *'(A)lways'* ]] && return 0
    [[ "$content" == *'Allow?'* ]] && return 0
    [[ "$content" == *'[y/n]'* ]] && return 0
    [[ "$content" == *'[Y/n]'* ]] && return 0
    [[ "$content" == *'(y/n)'* ]] && return 0
    [[ "$content" == *'(yes/no)'* ]] && return 0
    [[ "$content" == *'proceed?'* ]] && return 0
    return 1
}

__atm_screen_monitor() {
    exec >/dev/null 2>&1

    local interval=${AI_TAB_POLL_INTERVAL:-1}
    local state_dir="/tmp/ai-tab-monitor-${ZELLIJ_SESSION_NAME}"
    local dumpfile="${state_dir}/pane-${ZELLIJ_PANE_ID}.dump"
    local prev_hash=""
    local stable_ticks=0
    local state="idle"

    sleep 1

    while true; do
        zellij action dump-screen "$dumpfile" 2>/dev/null || { sleep "$interval"; continue; }

        local curr_hash
        if command -v md5 >/dev/null 2>&1; then
            curr_hash=$(sed 's/[[:space:]]*$//' "$dumpfile" 2>/dev/null | md5 -q 2>/dev/null)
        else
            curr_hash=$(sed 's/[[:space:]]*$//' "$dumpfile" 2>/dev/null | md5sum 2>/dev/null | cut -d' ' -f1)
        fi

        [[ -z "$curr_hash" ]] && { sleep "$interval"; continue; }

        if [[ -z "$prev_hash" ]]; then
            prev_hash="$curr_hash"
            sleep "$interval"
            continue
        fi

        local new_state="$state"
        if [[ "$curr_hash" != "$prev_hash" ]]; then
            new_state="working"
            stable_ticks=0
        else
            stable_ticks=$((stable_ticks + 1))
            if [[ $stable_ticks -ge 3 ]]; then
                local content
                content=$(tail -10 "$dumpfile" 2>/dev/null)
                if __atm_is_waiting "$content"; then
                    new_state="waiting"
                else
                    new_state="idle"
                fi
            fi
        fi

        prev_hash="$curr_hash"
        if [[ "$new_state" != "$state" ]]; then
            state="$new_state"
            bash "$__ATM_HOOK" "$state"
        fi

        sleep "$interval"
    done
}

cursor-agent() {
    if [[ -n "$ZELLIJ" ]] && [[ -n "$ZELLIJ_PANE_ID" ]]; then
        local state_dir="/tmp/ai-tab-monitor-${ZELLIJ_SESSION_NAME}"
        __atm_capture_orig_name
        mkdir -p "$state_dir" 2>/dev/null
        printf '%s' "$$" > "${state_dir}/pane-${ZELLIJ_PANE_ID}.pid"
        bash "$__ATM_HOOK" idle

        __atm_screen_monitor </dev/null &
        local _monitor_pid=$!
        disown $_monitor_pid 2>/dev/null

        local _exit
        {
            command cursor-agent "$@"
            _exit=$?
        } always {
            kill $_monitor_pid 2>/dev/null
            wait $_monitor_pid 2>/dev/null
            rm -f "${state_dir}/pane-${ZELLIJ_PANE_ID}.dump" 2>/dev/null
            rm -f "${state_dir}/pane-${ZELLIJ_PANE_ID}.pid" 2>/dev/null
            bash "$__ATM_HOOK" cleanup 2>/dev/null
        }
        return ${_exit:-0}
    else
        command cursor-agent "$@"
    fi
}
