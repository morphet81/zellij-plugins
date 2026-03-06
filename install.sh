#!/usr/bin/env bash
set -euo pipefail

REPO="morphet81/zellij-plugins"
RAW_URL="https://raw.githubusercontent.com/${REPO}/main"
INSTALL_DIR="${ZELLIJ_PLUGIN_DIR:-${HOME}/.config/zellij/plugins}"

usage() {
    cat <<EOF
Install zellij-plugins from GitHub.

Usage: install.sh [OPTIONS]

Options:
  -d, --dir <path>   Install directory (default: ~/.config/zellij/plugins)
  -h, --help         Show this help

One-liner:
  curl -fsSL https://raw.githubusercontent.com/${REPO}/main/install.sh | bash
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dir) INSTALL_DIR="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1"; usage; exit 1 ;;
    esac
done

# --- Install plugin files ---
echo "Installing to ${INSTALL_DIR} ..."
mkdir -p "$INSTALL_DIR"

curl -fsSL "${RAW_URL}/ai-tab-monitor.zsh" -o "${INSTALL_DIR}/ai-tab-monitor.zsh"
curl -fsSL "${RAW_URL}/ai-tab-monitor-hook.sh" -o "${INSTALL_DIR}/ai-tab-monitor-hook.sh"
chmod +x "${INSTALL_DIR}/ai-tab-monitor.zsh" "${INSTALL_DIR}/ai-tab-monitor-hook.sh"

echo "Installed ai-tab-monitor.zsh and ai-tab-monitor-hook.sh"

# --- Source line in .zshrc ---
SHELL_RC=""
if [[ -n "${ZSH_VERSION:-}" ]] || [[ "$SHELL" == */zsh ]]; then
    SHELL_RC="${HOME}/.zshrc"
fi

SOURCE_LINE="source \"${INSTALL_DIR}/ai-tab-monitor.zsh\""

if [[ -n "$SHELL_RC" ]]; then
    if grep -qF "ai-tab-monitor.zsh" "$SHELL_RC" 2>/dev/null; then
        echo "Already sourced in ${SHELL_RC}"
    else
        if [[ -t 0 ]]; then
            read -rp "Add source line to ${SHELL_RC}? [Y/n] " answer
        elif [[ -e /dev/tty ]]; then
            read -rp "Add source line to ${SHELL_RC}? [Y/n] " answer </dev/tty
        else
            answer="Y"
            echo "Add source line to ${SHELL_RC}? [Y/n] Y (auto-accepted, non-interactive)"
        fi
        answer="${answer:-Y}"
        if [[ "$answer" =~ ^[Yy] ]]; then
            echo "" >> "$SHELL_RC"
            echo "# Zellij AI tab monitor (claude, cursor-agent)" >> "$SHELL_RC"
            echo "${SOURCE_LINE}" >> "$SHELL_RC"
            echo "Added to ${SHELL_RC}"
        else
            echo "Skipped. Add manually:"
            echo "  ${SOURCE_LINE}"
        fi
    fi
else
    echo ""
    echo "Add this to your .zshrc:"
    echo "  ${SOURCE_LINE}"
fi

# --- Claude Code hooks in settings.json ---
CLAUDE_SETTINGS="${HOME}/.claude/settings.json"
HOOK_PATH="${INSTALL_DIR}/ai-tab-monitor-hook.sh"

setup_hooks() {
    if ! command -v jq >/dev/null 2>&1; then
        echo ""
        echo "jq is required to configure Claude Code hooks automatically."
        echo "Install jq, then re-run this script, or add hooks manually (see README)."
        return
    fi

    if [[ ! -f "$CLAUDE_SETTINGS" ]]; then
        echo ""
        echo "Claude Code settings not found at ${CLAUDE_SETTINGS}."
        echo "Run claude once to create it, then re-run this script, or add hooks manually (see README)."
        return
    fi

    # Check if our hooks are already present by looking for our hook script path in the file
    if grep -qF "ai-tab-monitor-hook.sh" "$CLAUDE_SETTINGS" 2>/dev/null; then
        echo "Claude Code hooks already configured in ${CLAUDE_SETTINGS}"
        return
    fi

    if [[ -t 0 ]]; then
        read -rp "Add Claude Code hooks to ${CLAUDE_SETTINGS}? [Y/n] " answer
    elif [[ -e /dev/tty ]]; then
        read -rp "Add Claude Code hooks to ${CLAUDE_SETTINGS}? [Y/n] " answer </dev/tty
    else
        answer="Y"
        echo "Add Claude Code hooks to ${CLAUDE_SETTINGS}? [Y/n] Y (auto-accepted, non-interactive)"
    fi
    answer="${answer:-Y}"
    if [[ ! "$answer" =~ ^[Yy] ]]; then
        echo "Skipped hooks setup. See README for manual configuration."
        return
    fi

    HOOK_CMD="bash \"${HOOK_PATH}\""

    # Ensure .hooks exists, then add our hook entries
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
        | .hooks.SessionEnd = ((.hooks.SessionEnd // []) + [
            {"matcher": "", "hooks": [{"type": "command", "command": ($hook_cmd + " cleanup")}]}
          ])
        | .hooks.Notification = ((.hooks.Notification // []) + [
            {"matcher": "permission_prompt", "hooks": [{"type": "command", "command": ($hook_cmd + " waiting")}]},
            {"matcher": "idle_prompt", "hooks": [{"type": "command", "command": ($hook_cmd + " idle")}]},
            {"matcher": "elicitation_dialog", "hooks": [{"type": "command", "command": ($hook_cmd + " waiting")}]}
          ])
    ' "$CLAUDE_SETTINGS" > "${CLAUDE_SETTINGS}.tmp" && mv "${CLAUDE_SETTINGS}.tmp" "$CLAUDE_SETTINGS"

    echo "Added Claude Code hooks to ${CLAUDE_SETTINGS}"
}

setup_hooks

echo ""
echo "Done! Restart your shell or run:"
echo "  source \"${INSTALL_DIR}/ai-tab-monitor.zsh\""
