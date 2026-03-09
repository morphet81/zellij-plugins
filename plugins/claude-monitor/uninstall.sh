#!/usr/bin/env bash
# Plugin-specific uninstaller for Claude Monitor
# Called by root uninstall.sh with INSTALL_DIR exported
set -euo pipefail

# --- Remove Claude Code hooks from settings.json ---
CLAUDE_SETTINGS="${HOME}/.claude/settings.json"

if [[ -f "$CLAUDE_SETTINGS" ]] && grep -qF "hook.sh" "$CLAUDE_SETTINGS" 2>/dev/null; then
    if command -v jq >/dev/null 2>&1; then
        if confirm "Remove Claude Code hooks from ${CLAUDE_SETTINGS}?"; then
            jq '
                .hooks |= (if . then
                    with_entries(
                        .value |= map(
                            .hooks |= map(select(.command | tostring | contains("hook.sh") | not))
                            | select(.hooks | length > 0)
                        )
                        | select(.value | length > 0)
                    )
                else . end)
            ' "$CLAUDE_SETTINGS" > "${CLAUDE_SETTINGS}.tmp" && mv "${CLAUDE_SETTINGS}.tmp" "$CLAUDE_SETTINGS"
            success "Removed Claude Code hooks from ${CLAUDE_SETTINGS}"
        else
            warn "Skipped removing hooks."
        fi
    else
        warn "jq not found. Please manually remove hook.sh entries from ${CLAUDE_SETTINGS}"
    fi
else
    info "No Claude Code hooks to remove."
fi

# --- Remove legacy source lines from .zshrc ---
if [[ -f "${HOME}/.zshrc" ]] && grep -qE "claude-monitor\.zsh|ai-tab-monitor\.zsh" "${HOME}/.zshrc" 2>/dev/null; then
    if confirm "Remove legacy source line from ~/.zshrc?"; then
        sed -i.bak '/# Claude Tab Monitor/d;/claude-monitor\.zsh/d;/ai-tab-monitor\.zsh/d' "${HOME}/.zshrc"
        rm -f "${HOME}/.zshrc.bak"
        success "Removed legacy source line from ~/.zshrc"
    fi
fi

# --- Remove plugin files ---
removed=false
for f in claude-tab-monitor.wasm hook.sh claude-monitor.zsh ai-tab-monitor.zsh ai-tab-monitor-hook.sh; do
    if [[ -f "${INSTALL_DIR}/${f}" ]]; then
        rm -f "${INSTALL_DIR}/${f}"
        removed=true
        success "Removed ${INSTALL_DIR}/${f}"
    fi
done

if ! $removed; then
    info "No plugin files found in ${INSTALL_DIR}"
fi

# --- Clean up legacy temp state files ---
rm -rf /tmp/ai-tab-monitor-* 2>/dev/null || true
