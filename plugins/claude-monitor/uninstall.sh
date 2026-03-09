#!/usr/bin/env bash
# Plugin-specific uninstaller for Claude Monitor
# Called by root uninstall.sh with INSTALL_DIR exported
set -euo pipefail

# --- Remove Claude Code hooks from settings.json ---
CLAUDE_SETTINGS="${HOME}/.claude/settings.json"
HOOK_CMD="${INSTALL_DIR}/hook.sh"

# Check for plugin hooks by the specific installed path, with fallback to generic detection
has_plugin_hooks=false
if [[ -f "$CLAUDE_SETTINGS" ]]; then
    if grep -qF "$HOOK_CMD" "$CLAUDE_SETTINGS" 2>/dev/null; then
        has_plugin_hooks=true
    elif grep -qF "hook.sh" "$CLAUDE_SETTINGS" 2>/dev/null; then
        # Check if any hook.sh entries look like ours (contain "zellij" in path)
        if command -v jq >/dev/null 2>&1; then
            if jq -e '.hooks // {} | to_entries[] | .value[]? | .hooks[]? | select(.command | tostring | (contains("hook.sh") and contains("zellij")))' "$CLAUDE_SETTINGS" >/dev/null 2>&1; then
                has_plugin_hooks=true
            fi
        fi
    fi
fi

if $has_plugin_hooks; then
    if command -v jq >/dev/null 2>&1; then
        if confirm "Remove Claude Monitor hooks from ${CLAUDE_SETTINGS}?"; then
            # Remove entries whose command contains our hook path or legacy zellij hook paths.
            # Preserves other hooks in the same event type (e.g. user's notify-send).
            jq --arg path "$HOOK_CMD" '
                .hooks |= (if . then
                    with_entries(
                        .value |= map(
                            .hooks |= map(select(.command | tostring | (contains($path) or (contains("hook.sh") and contains("zellij"))) | not))
                            | select(.hooks | length > 0)
                        )
                    )
                else . end)
            ' "$CLAUDE_SETTINGS" > "${CLAUDE_SETTINGS}.tmp" && mv "${CLAUDE_SETTINGS}.tmp" "$CLAUDE_SETTINGS"
            success "Removed Claude Monitor hooks from ${CLAUDE_SETTINGS}"
        else
            warn "Skipped removing hooks."
        fi
    else
        warn "jq not found. Please manually remove hook.sh entries from ${CLAUDE_SETTINGS}"
    fi
else
    info "No Claude Monitor hooks to remove."
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
