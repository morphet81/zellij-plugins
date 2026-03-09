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

export INSTALL_DIR="${ZELLIJ_PLUGIN_DIR:-${HOME}/.config/zellij/plugins}"

usage() {
    cat <<EOF
${BOLD}Zellij Plugins - Uninstaller${NC}

Usage: uninstall.sh [OPTIONS]

Options:
  -d, --dir <path>   Install directory (default: ~/.config/zellij/plugins)
  -y, --yes          Skip confirmation prompts, uninstall all installed plugins
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BOLD}Zellij Plugins - Uninstaller${NC}"
echo ""

# --- Discover installed plugins ---
declare -a plugin_dirs=()
declare -a plugin_names=()
declare -a plugin_descs=()
declare -a plugin_selected=()

for conf in "${SCRIPT_DIR}"/plugins/*/plugin.conf; do
    [[ -f "$conf" ]] || continue
    plugin_dir="$(dirname "$conf")"

    PLUGIN_NAME="" PLUGIN_DESC="" WASM_NAME=""
    source "$conf"

    # Only show plugins that appear to be installed
    if [[ -f "${INSTALL_DIR}/${WASM_NAME}" ]]; then
        plugin_dirs+=("$plugin_dir")
        plugin_names+=("$PLUGIN_NAME")
        plugin_descs+=("$PLUGIN_DESC")
        plugin_selected+=(1)  # All selected by default
    fi
done

if [[ ${#plugin_dirs[@]} -eq 0 ]]; then
    info "No installed plugins found in ${INSTALL_DIR}"
    exit 0
fi

# --- Interactive selector ---
select_plugins() {
    local count=${#plugin_names[@]}
    local cursor=0

    local saved_tty
    saved_tty=$(stty -g </dev/tty 2>/dev/null)

    draw() {
        if [[ "${1:-}" == "redraw" ]]; then
            printf '\033[%dA' "$((count + 2))" >/dev/tty
        fi
        echo -e "${BOLD}Select plugins to uninstall:${NC}  (↑/↓ navigate, Space toggle, Enter confirm)" >/dev/tty
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

    while true; do
        stty raw -echo </dev/tty 2>/dev/null
        local key
        key=$(dd bs=1 count=1 2>/dev/null </dev/tty)
        local key_code
        key_code=$(printf '%d' "'$key" 2>/dev/null || echo 0)

        if [[ "$key_code" -eq 27 ]]; then
            local seq1 seq2
            seq1=$(dd bs=1 count=1 2>/dev/null </dev/tty)
            seq2=$(dd bs=1 count=1 2>/dev/null </dev/tty)
            stty "$saved_tty" </dev/tty 2>/dev/null
            if [[ "$seq1" == "[" ]]; then
                case "$seq2" in
                    A) [[ $cursor -gt 0 ]] && cursor=$((cursor - 1)) ;;
                    B) [[ $cursor -lt $((count - 1)) ]] && cursor=$((cursor + 1)) ;;
                esac
            fi
        elif [[ "$key" == " " ]]; then
            stty "$saved_tty" </dev/tty 2>/dev/null
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
        info "Non-interactive mode: uninstalling all plugins"
    fi
fi

# --- Uninstall selected plugins ---
uninstalled=0
for i in "${!plugin_dirs[@]}"; do
    if [[ ${plugin_selected[$i]} -eq 1 ]]; then
        echo ""
        echo -e "${BOLD}Uninstalling ${plugin_names[$i]}...${NC}"
        echo ""
        source "${plugin_dirs[$i]}/uninstall.sh"
        uninstalled=$((uninstalled + 1))
    fi
done

if [[ $uninstalled -eq 0 ]]; then
    warn "No plugins selected."
    exit 0
fi

echo ""
success "Uninstall complete! (${uninstalled} plugin(s) removed)"
