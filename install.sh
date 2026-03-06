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

echo "Installing to ${INSTALL_DIR} ..."
mkdir -p "$INSTALL_DIR"

curl -fsSL "${RAW_URL}/ai-tab-monitor.zsh" -o "${INSTALL_DIR}/ai-tab-monitor.zsh"
chmod +x "${INSTALL_DIR}/ai-tab-monitor.zsh"

echo "Installed ai-tab-monitor.zsh"

SHELL_RC=""
if [[ -n "${ZSH_VERSION:-}" ]] || [[ "$SHELL" == */zsh ]]; then
    SHELL_RC="${HOME}/.zshrc"
fi

SOURCE_LINE="source \"${INSTALL_DIR}/ai-tab-monitor.zsh\""

if [[ -n "$SHELL_RC" ]]; then
    if grep -qF "ai-tab-monitor.zsh" "$SHELL_RC" 2>/dev/null; then
        echo "Already sourced in ${SHELL_RC}"
    else
        read -rp "Add source line to ${SHELL_RC}? [Y/n] " answer
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

echo ""
echo "Done! Restart your shell or run:"
echo "  source \"${INSTALL_DIR}/ai-tab-monitor.zsh\""
