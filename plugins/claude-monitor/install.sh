#!/usr/bin/env bash
# Plugin-specific installer for Claude Monitor
# Called by root install.sh with INSTALL_DIR exported
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Build WASM plugin ---
WASM_FILE="${PLUGIN_DIR}/plugin/target/wasm32-wasip1/release/claude-tab-monitor.wasm"

if [[ -f "$WASM_FILE" ]]; then
    success "WASM plugin already built"
else
    info "Building WASM plugin..."

    # Check for Rust toolchain
    if ! command -v cargo >/dev/null 2>&1; then
        if [[ -f "${HOME}/.cargo/env" ]]; then
            source "${HOME}/.cargo/env"
        fi
    fi

    if ! command -v cargo >/dev/null 2>&1; then
        error "Rust toolchain not found. Install it with:"
        echo "  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
        echo "  rustup target add wasm32-wasip1"
        return 1
    fi

    # Ensure wasm32-wasip1 target is available
    if ! rustup target list --installed 2>/dev/null | grep -q wasm32-wasip1; then
        info "Adding wasm32-wasip1 target..."
        rustup target add wasm32-wasip1
    fi

    (cd "${PLUGIN_DIR}/plugin" && cargo build --release --target wasm32-wasip1)
    success "Built WASM plugin"
fi

cp "$WASM_FILE" "${INSTALL_DIR}/claude-tab-monitor.wasm"
success "Installed claude-tab-monitor.wasm"

cp "${PLUGIN_DIR}/hook.sh" "${INSTALL_DIR}/hook.sh"
chmod +x "${INSTALL_DIR}/hook.sh"
success "Installed hook.sh"

# --- Claude Code hooks in settings.json ---
CLAUDE_SETTINGS="${HOME}/.claude/settings.json"
HOOK_CMD="${INSTALL_DIR}/hook.sh"

if ! command -v jq >/dev/null 2>&1; then
    warn "jq is required to configure Claude Code hooks automatically."
    warn "Install jq, then re-run this script, or add hooks manually (see README)."
    return 0
fi

if [[ ! -f "$CLAUDE_SETTINGS" ]]; then
    warn "Claude Code settings not found at ${CLAUDE_SETTINGS}."
    warn "Run 'claude' once to create it, then re-run this script."
    return 0
fi

# Check if hooks are already configured
if grep -qF "hook.sh" "$CLAUDE_SETTINGS" 2>/dev/null; then
    success "Claude Code hooks already configured in ${CLAUDE_SETTINGS}"
    return 0
fi

if ! confirm "Add Claude Code hooks to ${CLAUDE_SETTINGS}?"; then
    warn "Skipped hooks setup. See README for manual configuration."
    return 0
fi

jq --arg hook_cmd "$HOOK_CMD" '
    .hooks //= {}
    | .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) + [
        {"matcher": "", "hooks": [{"type": "command", "command": ($hook_cmd + " working")}]}
      ])
    | .hooks.PostToolUse = ((.hooks.PostToolUse // []) + [
        {"matcher": "", "hooks": [{"type": "command", "command": ($hook_cmd + " working")}]}
      ])
    | .hooks.Stop = ((.hooks.Stop // []) + [
        {"matcher": "", "hooks": [{"type": "command", "command": ($hook_cmd + " idle")}]}
      ])
    | .hooks.Notification = ((.hooks.Notification // []) + [
        {"matcher": "permission_prompt", "hooks": [{"type": "command", "command": ($hook_cmd + " waiting")}]},
        {"matcher": "idle_prompt", "hooks": [{"type": "command", "command": ($hook_cmd + " idle")}]},
        {"matcher": "elicitation_dialog", "hooks": [{"type": "command", "command": ($hook_cmd + " waiting")}]}
      ])
    | .hooks.SessionEnd = ((.hooks.SessionEnd // []) + [
        {"matcher": "", "hooks": [{"type": "command", "command": ($hook_cmd + " exit")}]}
      ])
' "$CLAUDE_SETTINGS" > "${CLAUDE_SETTINGS}.tmp" && mv "${CLAUDE_SETTINGS}.tmp" "$CLAUDE_SETTINGS"

success "Added Claude Code hooks to ${CLAUDE_SETTINGS}"
