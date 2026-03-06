#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${ZELLIJ_PLUGIN_DIR:-${HOME}/.config/zellij/plugins}"

usage() {
    cat <<EOF
Uninstall zellij-plugins.

Usage: uninstall.sh [OPTIONS]

Options:
  -d, --dir <path>   Install directory (default: ~/.config/zellij/plugins)
  -h, --help         Show this help

One-liner:
  curl -fsSL https://raw.githubusercontent.com/morphet81/zellij-plugins/main/uninstall.sh | bash
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dir) INSTALL_DIR="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1"; usage; exit 1 ;;
    esac
done

# --- Remove Claude Code hooks from settings.json ---
CLAUDE_SETTINGS="${HOME}/.claude/settings.json"

if [[ -f "$CLAUDE_SETTINGS" ]] && grep -qF "ai-tab-monitor-hook.sh" "$CLAUDE_SETTINGS" 2>/dev/null; then
    if command -v jq >/dev/null 2>&1; then
        # Remove any hook entry whose command contains our hook script
        jq '
            .hooks |= (if . then
                with_entries(
                    .value |= map(
                        # For each hook group entry, filter out hooks referencing our script
                        .hooks |= map(select(.command | tostring | contains("ai-tab-monitor-hook.sh") | not))
                        | select(.hooks | length > 0)
                    )
                    | select(.value | length > 0)
                )
            else . end)
        ' "$CLAUDE_SETTINGS" > "${CLAUDE_SETTINGS}.tmp" && mv "${CLAUDE_SETTINGS}.tmp" "$CLAUDE_SETTINGS"
        echo "Removed Claude Code hooks from ${CLAUDE_SETTINGS}"
    else
        echo "Warning: jq not found. Please manually remove ai-tab-monitor-hook.sh entries from ${CLAUDE_SETTINGS}"
    fi
else
    echo "No Claude Code hooks to remove."
fi

# --- Remove source line from .zshrc ---
SHELL_RC=""
if [[ -n "${ZSH_VERSION:-}" ]] || [[ "$SHELL" == */zsh ]]; then
    SHELL_RC="${HOME}/.zshrc"
fi

if [[ -n "$SHELL_RC" ]] && [[ -f "$SHELL_RC" ]]; then
    if grep -qF "ai-tab-monitor.zsh" "$SHELL_RC" 2>/dev/null; then
        # Remove the source line and its comment
        sed -i.bak '/# Zellij AI tab monitor/d;/ai-tab-monitor\.zsh/d' "$SHELL_RC"
        rm -f "${SHELL_RC}.bak"
        echo "Removed source line from ${SHELL_RC}"
    fi
fi

# --- Remove plugin files ---
removed=false
for f in ai-tab-monitor.zsh ai-tab-monitor-hook.sh; do
    if [[ -f "${INSTALL_DIR}/${f}" ]]; then
        rm -f "${INSTALL_DIR}/${f}"
        removed=true
    fi
done

if $removed; then
    echo "Removed plugin files from ${INSTALL_DIR}"
else
    echo "No plugin files found in ${INSTALL_DIR}"
fi

# --- Clean up temp state files ---
rm -rf /tmp/ai-tab-monitor-* 2>/dev/null && echo "Cleaned up temporary state files."

echo ""
echo "Done! Restart your shell to complete uninstall."
