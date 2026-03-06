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

REPO="morphet81/zellij-plugins"
RAW_URL="https://raw.githubusercontent.com/${REPO}/main"
RELEASE_URL="https://github.com/${REPO}/releases/latest/download"
INSTALL_DIR="${ZELLIJ_PLUGIN_DIR:-${HOME}/.config/zellij/plugins}"

usage() {
    cat <<EOF
${BOLD}Claude Tab Monitor - Installer${NC}

Usage: install.sh [OPTIONS]

Options:
  -d, --dir <path>   Install directory (default: ~/.config/zellij/plugins)
  -y, --yes          Skip confirmation prompts
  -h, --help         Show this help

One-liner:
  curl -fsSL ${RAW_URL}/install.sh | bash
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

echo -e "${BOLD}Claude Tab Monitor - Installer${NC}"
echo ""

# --- Check prerequisites ---
if ! command -v zellij >/dev/null 2>&1; then
    error "zellij is not installed. Please install it first: https://zellij.dev/documentation/installation"
    exit 1
fi
success "zellij found: $(zellij --version 2>/dev/null || echo 'unknown version')"

if ! command -v curl >/dev/null 2>&1; then
    error "curl is required but not found."
    exit 1
fi

# --- Create plugin directory ---
info "Install directory: ${INSTALL_DIR}"
mkdir -p "$INSTALL_DIR"

# --- Download files ---
info "Downloading plugin files..."

curl -fsSL "${RELEASE_URL}/claude-tab-monitor.wasm" -o "${INSTALL_DIR}/claude-tab-monitor.wasm"
success "Downloaded claude-tab-monitor.wasm"

curl -fsSL "${RAW_URL}/hook.sh" -o "${INSTALL_DIR}/hook.sh"
chmod +x "${INSTALL_DIR}/hook.sh"
success "Downloaded hook.sh"

# --- Claude Code hooks in settings.json ---
echo ""
CLAUDE_SETTINGS="${HOME}/.claude/settings.json"
HOOK_CMD="\$HOME/.config/zellij/plugins/hook.sh"

setup_hooks() {
    if ! command -v jq >/dev/null 2>&1; then
        warn "jq is required to configure Claude Code hooks automatically."
        warn "Install jq, then re-run this script, or add hooks manually (see README)."
        return
    fi

    if [[ ! -f "$CLAUDE_SETTINGS" ]]; then
        warn "Claude Code settings not found at ${CLAUDE_SETTINGS}."
        warn "Run 'claude' once to create it, then re-run this script."
        return
    fi

    # Check if hooks are already configured
    if grep -qF "hook.sh" "$CLAUDE_SETTINGS" 2>/dev/null; then
        success "Claude Code hooks already configured in ${CLAUDE_SETTINGS}"
        return
    fi

    if ! confirm "Add Claude Code hooks to ${CLAUDE_SETTINGS}?"; then
        warn "Skipped hooks setup. See README for manual configuration."
        return
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
}

setup_hooks

# --- Instructions ---
echo ""
echo -e "${BOLD}Installation complete!${NC}"
echo ""
echo -e "${CYAN}To start the plugin in Zellij, run:${NC}"
echo "  zellij plugin -- file:${INSTALL_DIR}/claude-tab-monitor.wasm"
echo ""
echo -e "${CYAN}Or add it to your Zellij layout:${NC}"
echo "  pane plugin location=\"file:${INSTALL_DIR}/claude-tab-monitor.wasm\""
echo ""
echo -e "${CYAN}Grant the plugin permissions when prompted.${NC}"
