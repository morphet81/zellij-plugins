#!/usr/bin/env bash
set -euo pipefail

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${CYAN}[*]${NC} $*"; }
success() { echo -e "${GREEN}[+]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[-]${NC} $*"; }

INSTALL_DIR="${ZELLIJ_PLUGIN_DIR:-${HOME}/.config/zellij/plugins}"

usage() {
    cat <<EOF
${BOLD}Claude Tab Monitor - Uninstaller${NC}

Usage: uninstall.sh [OPTIONS]

Options:
  -d, --dir <path>   Install directory (default: ~/.config/zellij/plugins)
  -y, --yes          Skip confirmation prompts
  -h, --help         Show this help

One-liner:
  curl -fsSL https://raw.githubusercontent.com/morphet81/zellij-plugins/main/uninstall.sh | bash
EOF
}

AUTO_YES=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dir) INSTALL_DIR="$2"; shift 2 ;;
        -y|--yes) AUTO_YES=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) error "Unknown option: $1"; usage; exit 1 ;;
    esac
done

# Prompt helper: returns 0 for yes, 1 for no
confirm() {
    local prompt="$1"
    if $AUTO_YES; then
        echo -e "${CYAN}[*]${NC} ${prompt} [Y/n] Y (auto-accepted)"
        return 0
    fi
    local answer
    if [[ -t 0 ]]; then
        read -rp "$(echo -e "${CYAN}[*]${NC} ${prompt} [Y/n] ")" answer
    elif [[ -e /dev/tty ]]; then
        read -rp "$(echo -e "${CYAN}[*]${NC} ${prompt} [Y/n] ")" answer </dev/tty
    else
        echo -e "${CYAN}[*]${NC} ${prompt} [Y/n] Y (auto-accepted, non-interactive)"
        return 0
    fi
    answer="${answer:-Y}"
    [[ "$answer" =~ ^[Yy] ]]
}

echo -e "${BOLD}Claude Tab Monitor - Uninstaller${NC}"
echo ""

# --- Remove Claude Code hooks from settings.json ---
CLAUDE_SETTINGS="${HOME}/.claude/settings.json"

if [[ -f "$CLAUDE_SETTINGS" ]] && grep -qF "hook.sh" "$CLAUDE_SETTINGS" 2>/dev/null; then
    if command -v jq >/dev/null 2>&1; then
        if confirm "Remove Claude Code hooks from ${CLAUDE_SETTINGS}?"; then
            # Remove any hook entry whose command contains our hook script
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

# --- Remove source line from .zshrc ---
SHELL_RC=""
if [[ -n "${ZSH_VERSION:-}" ]] || [[ "$SHELL" == */zsh ]]; then
    SHELL_RC="${HOME}/.zshrc"
fi

if [[ -n "$SHELL_RC" ]] && [[ -f "$SHELL_RC" ]]; then
    if grep -qF "claude-monitor.zsh" "$SHELL_RC" 2>/dev/null; then
        if confirm "Remove source line from ${SHELL_RC}?"; then
            sed -i.bak '/# Claude Tab Monitor/d;/claude-monitor\.zsh/d' "$SHELL_RC"
            rm -f "${SHELL_RC}.bak"
            success "Removed source line from ${SHELL_RC}"
        else
            warn "Skipped removing source line."
        fi
    else
        info "No source line found in ${SHELL_RC}"
    fi
fi

# --- Remove plugin files ---
removed=false
for f in claude-tab-monitor.wasm hook.sh claude-monitor.zsh; do
    if [[ -f "${INSTALL_DIR}/${f}" ]]; then
        rm -f "${INSTALL_DIR}/${f}"
        removed=true
        success "Removed ${INSTALL_DIR}/${f}"
    fi
done

# Also clean up old file names from previous versions
for f in ai-tab-monitor.zsh ai-tab-monitor-hook.sh; do
    if [[ -f "${INSTALL_DIR}/${f}" ]]; then
        rm -f "${INSTALL_DIR}/${f}"
        removed=true
        success "Removed legacy file ${INSTALL_DIR}/${f}"
    fi
done

if ! $removed; then
    info "No plugin files found in ${INSTALL_DIR}"
fi

# --- Clean up temp state files ---
rm -rf /tmp/ai-tab-monitor-* 2>/dev/null || true

echo ""
success "Uninstall complete! Restart your shell to finish."
