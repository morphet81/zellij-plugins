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
export INSTALL_DIR="${ZELLIJ_PLUGIN_DIR:-${HOME}/.config/zellij/plugins}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat <<EOF
${BOLD}Zellij Plugins - Installer${NC}

Usage: install.sh [OPTIONS]

Options:
  -d, --dir <path>   Install directory (default: ~/.config/zellij/plugins)
  -y, --yes          Skip confirmation prompts, install all plugins
  -h, --help         Show this help
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

# Export utilities so plugin scripts can use them
export -f info success warn error confirm
export AUTO_YES
export RED GREEN YELLOW CYAN BOLD NC

echo -e "${BOLD}Zellij Plugins - Installer${NC}"
echo ""

# --- Check prerequisites ---
if ! command -v zellij >/dev/null 2>&1; then
    error "zellij is not installed. Please install it first: https://zellij.dev/documentation/installation"
    exit 1
fi
success "zellij found: $(zellij --version 2>/dev/null || echo 'unknown version')"

# --- Discover plugins ---
declare -a plugin_dirs=()
declare -a plugin_names=()
declare -a plugin_descs=()
declare -a plugin_wasms=()
declare -a plugin_selected=()

for conf in "${SCRIPT_DIR}"/plugins/*/plugin.conf; do
    [[ -f "$conf" ]] || continue
    plugin_dir="$(dirname "$conf")"

    # Source in subshell to avoid polluting env
    PLUGIN_NAME="" PLUGIN_DESC="" WASM_NAME=""
    source "$conf"

    plugin_dirs+=("$plugin_dir")
    plugin_names+=("$PLUGIN_NAME")
    plugin_descs+=("$PLUGIN_DESC")
    plugin_wasms+=("$WASM_NAME")
    plugin_selected+=(1)  # All selected by default
done

if [[ ${#plugin_dirs[@]} -eq 0 ]]; then
    error "No plugins found in ${SCRIPT_DIR}/plugins/"
    exit 1
fi

# --- Interactive selector ---
select_plugins() {
    local count=${#plugin_names[@]}
    local cursor=0

    # Save terminal state and enable raw mode
    local saved_tty
    saved_tty=$(stty -g </dev/tty 2>/dev/null)

    draw() {
        # Move cursor up to redraw (except first draw)
        if [[ "${1:-}" == "redraw" ]]; then
            printf '\033[%dA' "$((count + 2))" >/dev/tty
        fi
        echo -e "${BOLD}Select plugins to install:${NC}  (↑/↓ navigate, Space toggle, Enter confirm)" >/dev/tty
        for i in $(seq 0 $((count - 1))); do
            local check=" "
            [[ ${plugin_selected[$i]} -eq 1 ]] && check="x"
            local marker="  "
            [[ $i -eq $cursor ]] && marker="> "
            if [[ $i -eq $cursor ]]; then
                echo -e "${marker}${BOLD}[${check}] ${plugin_names[$i]}${NC} - ${plugin_descs[$i]}" >/dev/tty
            else
                echo -e "${marker}[${check}] ${plugin_names[$i]} - ${plugin_descs[$i]}" >/dev/tty
            fi
        done
        echo "" >/dev/tty
    }

    draw

    # Read keys from /dev/tty
    while true; do
        stty raw -echo </dev/tty 2>/dev/null
        local key
        key=$(dd bs=1 count=1 2>/dev/null </dev/tty)
        local key_code
        key_code=$(printf '%d' "'$key" 2>/dev/null || echo 0)

        if [[ "$key_code" -eq 27 ]]; then
            # Escape sequence - read next chars
            local seq1 seq2
            seq1=$(dd bs=1 count=1 2>/dev/null </dev/tty)
            seq2=$(dd bs=1 count=1 2>/dev/null </dev/tty)
            stty "$saved_tty" </dev/tty 2>/dev/null
            if [[ "$seq1" == "[" ]]; then
                case "$seq2" in
                    A) # Up
                        [[ $cursor -gt 0 ]] && cursor=$((cursor - 1))
                        ;;
                    B) # Down
                        [[ $cursor -lt $((count - 1)) ]] && cursor=$((cursor + 1))
                        ;;
                esac
            fi
        elif [[ "$key" == " " ]]; then
            stty "$saved_tty" </dev/tty 2>/dev/null
            # Toggle
            if [[ ${plugin_selected[$cursor]} -eq 1 ]]; then
                plugin_selected[$cursor]=0
            else
                plugin_selected[$cursor]=1
            fi
        elif [[ "$key_code" -eq 13 ]] || [[ "$key_code" -eq 10 ]] || [[ "$key" == "" ]]; then
            stty "$saved_tty" </dev/tty 2>/dev/null
            break
        else
            stty "$saved_tty" </dev/tty 2>/dev/null
        fi
        draw "redraw"
    done
}

if ! $AUTO_YES; then
    if [[ -e /dev/tty ]]; then
        select_plugins
    else
        info "Non-interactive mode: installing all plugins"
    fi
fi

# --- Create plugin directory ---
info "Install directory: ${INSTALL_DIR}"
mkdir -p "$INSTALL_DIR"

# --- Install selected plugins ---
installed=0
for i in "${!plugin_dirs[@]}"; do
    if [[ ${plugin_selected[$i]} -eq 1 ]]; then
        echo ""
        echo -e "${BOLD}Installing ${plugin_names[$i]}...${NC}"
        echo ""
        source "${plugin_dirs[$i]}/install.sh"
        installed=$((installed + 1))
    fi
done

if [[ $installed -eq 0 ]]; then
    warn "No plugins selected."
    exit 0
fi

# --- Done ---
echo ""
echo -e "${BOLD}Installation complete! (${installed} plugin(s) installed)${NC}"
echo ""
echo -e "${CYAN}Plugins auto-launch when Claude Code hooks fire.${NC}"
echo -e "${CYAN}Grant Zellij plugin permissions when prompted on first use.${NC}"
echo ""
echo -e "${BOLD}To reload installed plugins in a running Zellij session:${NC}"
for i in "${!plugin_dirs[@]}"; do
    if [[ ${plugin_selected[$i]} -eq 1 ]]; then
        echo -e "  zellij action start-or-reload-plugin 'file:${INSTALL_DIR}/${plugin_wasms[$i]}'"
    fi
done
