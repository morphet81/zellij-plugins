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
    # Strip leftover icon prefix from a previous crashed session
    echo "${raw}" | sed 's/^[🟢🔵🟡] //'
}

__atm_capture_orig_name() {
    local state_dir="/tmp/ai-tab-monitor-${ZELLIJ_SESSION_NAME}"
    local orig_file="${state_dir}/pane-${ZELLIJ_PANE_ID}.orig"
    if [[ ! -f "$orig_file" ]]; then
        mkdir -p "$state_dir" 2>/dev/null
        __atm_get_tab_name > "$orig_file"
    fi
}

# --- Claude Code (hook-driven, no polling) ---------------------------------

claude() {
    if [[ -n "$ZELLIJ" ]] && [[ -n "$ZELLIJ_PANE_ID" ]]; then
        __atm_capture_orig_name
        bash "$__ATM_HOOK" idle

        command claude "$@"
        local _exit=$?

        # Safety-net cleanup (SessionEnd hook handles this normally)
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
        __atm_capture_orig_name
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
            rm -f "/tmp/ai-tab-monitor-${ZELLIJ_SESSION_NAME}/pane-${ZELLIJ_PANE_ID}.dump" 2>/dev/null
            bash "$__ATM_HOOK" cleanup 2>/dev/null
        }
        return ${_exit:-0}
    else
        command cursor-agent "$@"
    fi
}
