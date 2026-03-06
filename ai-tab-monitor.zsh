#!/usr/bin/env zsh
# ai-tab-monitor.zsh — Zellij tab indicator for Claude Code and Cursor Agent sessions
#
# Monitors terminal screen content to reliably detect agent states:
#   🟢 <tab name>  — idle (ready for a new query)
#   🔵 <tab name>  — working (processing/generating)
#   🟡 <tab name>  — waiting for user approval (permission prompt)
#   (original)     — restored when all sessions exit
#
# Source this in your .zshrc:
#   source /path/to/ai-tab-monitor.zsh
#
# Then just run `claude` or `cursor-agent` as usual.
#
# If a tab has multiple sessions, priority is: waiting > working > idle
#
# Configuration (optional env vars):
#   AI_TAB_POLL_INTERVAL  — seconds between checks (default: 0.5)
#   AI_TAB_WAITING_ICON   — icon for waiting state (default: 🟡)
#   AI_TAB_WORKING_ICON   — icon for working state (default: 🔵)
#   AI_TAB_IDLE_ICON      — icon for idle state (default: 🟢)

typeset -g __ATM_STATE_DIR="/tmp/ai-tab-monitor-${ZELLIJ_SESSION_NAME:-$$}-pane-${ZELLIJ_PANE_ID:-$$}"

__atm_monitor() {
    exec >/dev/null 2>&1

    local wrapper_pid=$1
    local monitor_id=$2
    local interval=${AI_TAB_POLL_INTERVAL:-0.5}
    local state_file="${__ATM_STATE_DIR}/${monitor_id}.state"
    local dumpfile="${__ATM_STATE_DIR}/${monitor_id}.dump"
    local prev_hash=""
    local stable_ticks=0
    local state="idle"

    mkdir -p "$__ATM_STATE_DIR" 2>/dev/null
    echo "idle" > "$state_file"
    __atm_update_tab

    sleep 1

    while kill -0 "$wrapper_pid" 2>/dev/null; do
        zellij action dump-screen "$dumpfile" 2>/dev/null

        local curr_hash
        if command -v md5 >/dev/null 2>&1; then
            curr_hash=$(sed 's/[[:space:]]*$//' "$dumpfile" 2>/dev/null | md5 -q 2>/dev/null)
        else
            curr_hash=$(sed 's/[[:space:]]*$//' "$dumpfile" 2>/dev/null | md5sum 2>/dev/null | cut -d' ' -f1)
        fi

        if [[ -z "$curr_hash" ]]; then
            sleep "$interval"
            continue
        fi

        # First check: just record baseline, stay idle
        if [[ -z "$prev_hash" ]]; then
            prev_hash="$curr_hash"
            sleep "$interval"
            continue
        fi

        if [[ "$curr_hash" != "$prev_hash" ]]; then
            # Screen content is changing → agent is producing output
            state="working"
            stable_ticks=0
        else
            stable_ticks=$((stable_ticks + 1))
            # After ~2 seconds of no screen changes, classify from content
            if [[ $stable_ticks -ge 4 ]]; then
                local content
                content=$(tail -10 "$dumpfile" 2>/dev/null)

                if __atm_is_waiting "$content"; then
                    state="waiting"
                else
                    state="idle"
                fi
            fi
            # During stabilization (< 4 ticks), keep previous state
        fi

        prev_hash="$curr_hash"
        echo "$state" > "$state_file"
        __atm_update_tab

        sleep "$interval"
    done

    # Process exited, clean up
    rm -f "$state_file" "$dumpfile" 2>/dev/null
    __atm_update_tab
}

__atm_is_waiting() {
    local content=$1
    # Claude Code approval prompts
    [[ "$content" == *'(Y)es'* ]] && return 0
    [[ "$content" == *'(N)o'* ]] && return 0
    [[ "$content" == *'(A)lways'* ]] && return 0
    [[ "$content" == *'Allow?'* ]] && return 0
    [[ "$content" == *'allow '* ]] && return 0
    # General approval patterns
    [[ "$content" == *'[y/n]'* ]] && return 0
    [[ "$content" == *'[Y/n]'* ]] && return 0
    [[ "$content" == *'(y/n)'* ]] && return 0
    [[ "$content" == *'(Y/n)'* ]] && return 0
    [[ "$content" == *'(yes/no)'* ]] && return 0
    [[ "$content" == *'proceed?'* ]] && return 0
    [[ "$content" == *'Approve'* ]] && return 0
    return 1
}

__atm_update_tab() {
    local waiting_icon=${AI_TAB_WAITING_ICON:-"🟡"}
    local working_icon=${AI_TAB_WORKING_ICON:-"🔵"}
    local idle_icon=${AI_TAB_IDLE_ICON:-"🟢"}

    local orig_name=""
    [[ -f "${__ATM_STATE_DIR}/.orig_name" ]] && orig_name=$(<"${__ATM_STATE_DIR}/.orig_name" 2>/dev/null)

    local overall="idle"
    local found=false

    for f in "${__ATM_STATE_DIR}"/*.state(N); do
        found=true
        local s
        s=$(<"$f" 2>/dev/null)
        case "$s" in
            waiting) overall="waiting" ;;
            working) [[ "$overall" != "waiting" ]] && overall="working" ;;
        esac
    done

    if ! $found; then
        zellij action undo-rename-tab 2>/dev/null
        rm -f "${__ATM_STATE_DIR}/.orig_name" 2>/dev/null
        return
    fi

    local icon
    case "$overall" in
        waiting) icon="$waiting_icon" ;;
        working) icon="$working_icon" ;;
        idle)    icon="$idle_icon" ;;
    esac

    zellij action rename-tab "${icon} ${orig_name}" 2>/dev/null
}

__atm_get_tab_name() {
    zellij action dump-layout 2>/dev/null \
        | grep -E 'tab.*focus=true' \
        | head -1 \
        | sed 's/.*name="\([^"]*\)".*/\1/'
}

__atm_wrap() {
    local cmd=$1
    shift

    if [[ -n "$ZELLIJ" ]]; then
        local monitor_id="${cmd}-$$-${RANDOM}"

        # Capture the original tab name before any renaming
        if [[ ! -f "${__ATM_STATE_DIR}/.orig_name" ]]; then
            mkdir -p "$__ATM_STATE_DIR" 2>/dev/null
            __atm_get_tab_name > "${__ATM_STATE_DIR}/.orig_name"
        fi
        local orig_name
        orig_name=$(<"${__ATM_STATE_DIR}/.orig_name" 2>/dev/null)

        __atm_monitor $$ "$monitor_id" </dev/null >/dev/null 2>&1 &
        local _monitor_pid=$!
        disown $_monitor_pid 2>/dev/null

        command "$cmd" "$@"
        local _exit=$?

        kill $_monitor_pid 2>/dev/null
        wait $_monitor_pid 2>/dev/null 2>&1
        rm -f "${__ATM_STATE_DIR}/${monitor_id}.state" "${__ATM_STATE_DIR}/${monitor_id}.dump" 2>/dev/null
        __atm_update_tab 2>/dev/null

        return $_exit
    else
        command "$cmd" "$@"
    fi
}

claude() { __atm_wrap claude "$@" }
cursor-agent() { __atm_wrap cursor-agent "$@" }
