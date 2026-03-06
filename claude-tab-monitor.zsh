#!/usr/bin/env zsh
# claude-tab-monitor.zsh — Zellij tab indicator for Claude Code sessions
#
# Source this in your .zshrc:
#   source ~/.config/zellij/claude-tab-monitor.zsh
#
# Then just run `claude` as usual. The tab name updates automatically:
#   🟡 Claude  — waiting for your input
#   🔵 Claude  — working (thinking or running tools)
#   (default)  — restored when Claude exits
#
# Configuration (optional env vars):
#   CLAUDE_TAB_POLL_INTERVAL  — seconds between checks (default: 2)
#   CLAUDE_TAB_WAITING_ICON   — icon for input-needed state (default: 🟡)
#   CLAUDE_TAB_WORKING_ICON   — icon for working state (default: 🔵)
#   CLAUDE_TAB_LABEL          — label text (default: Claude)

__ctm_poll() {
    # Suppress all output from this function
    exec >/dev/null 2>&1
    
    local shell_pid=$1
    local interval=${CLAUDE_TAB_POLL_INTERVAL:-2}
    local waiting=${CLAUDE_TAB_WAITING_ICON:-"🟡"}
    local working=${CLAUDE_TAB_WORKING_ICON:-"🔵"}
    local label=${CLAUDE_TAB_LABEL:-"Claude"}
    local prev_state=""

    sleep 1 # let claude start

    while true; do
        # Find the claude process among direct children of the shell
        local claude_pid=""
        local pids
        pids=($(pgrep -P "$shell_pid" 2>/dev/null))

        for pid in "${pids[@]}"; do
            local cmd
            cmd=$(ps -p "$pid" -o command= 2>/dev/null)
            if [[ "$cmd" == *claude* && "$cmd" != *__ctm_poll* ]]; then
                claude_pid=$pid
                break
            fi
        done

        [[ -z "$claude_pid" ]] && break

        # Detect state from child processes and CPU usage
        local tool_children
        tool_children=$(pgrep -P "$claude_pid" 2>/dev/null | wc -l | tr -d ' ')

        local cpu
        cpu=$(ps -p "$claude_pid" -o %cpu= 2>/dev/null | tr -d ' ')
        local cpu_int=${cpu%.*}

        local state
        if [[ "${tool_children:-0}" -gt 0 ]] || [[ "${cpu_int:-0}" -gt 3 ]]; then
            state="working"
        else
            state="waiting"
        fi

        # Only rename on state change to reduce noise
        if [[ "$state" != "$prev_state" ]]; then
            if [[ "$state" == "working" ]]; then
                zellij action rename-tab "${working} ${label}" 2>/dev/null
            else
                zellij action rename-tab "${waiting} ${label}" 2>/dev/null
            fi
            prev_state="$state"
        fi

        sleep "$interval"
    done
}

claude() {
    if [[ -n "$ZELLIJ" ]]; then
        # Start polling in background, redirecting all output to /dev/null
        __ctm_poll $$ </dev/null >/dev/null 2>&1 &
        local _ctm_pid=$!
        disown $_ctm_pid 2>/dev/null

        # Execute claude with all arguments, preserving stdin/stdout/stderr
        command claude "$@"
        local _exit=$?

        # Clean up background process silently
        kill $_ctm_pid 2>/dev/null
        wait $_ctm_pid 2>/dev/null 2>&1
        zellij action undo-rename-tab 2>/dev/null

        return $_exit
    else
        command claude "$@"
    fi
}
