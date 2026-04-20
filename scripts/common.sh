#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║              ShellLink — Common Utilities                    ║
# ╚══════════════════════════════════════════════════════════════╝
# Shared functions for all ShellLink bash scripts.

set -euo pipefail

# ── Colors ───────────────────────────────────────────────────
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    MAGENTA='\033[0;35m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    DIM='\033[2m'
    RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' MAGENTA='' CYAN='' BOLD='' DIM='' RESET=''
fi

# ── Logging ──────────────────────────────────────────────────
info()    { echo -e "${CYAN}  ℹ${RESET}  $*"; }
step()    { echo -e "${BLUE}  ▸${RESET}  $*"; }
success() { echo -e "${GREEN}  ✔${RESET}  $*"; }
warn()    { echo -e "${YELLOW}  ⚠${RESET}  $*" >&2; }
die()     { echo -e "${RED}  ✖${RESET}  $*" >&2; exit 1; }

# ── Banner ───────────────────────────────────────────────────
banner() {
    echo -e "${CYAN}${BOLD}"
    cat << 'EOF'

   _____ __         ____   __    _       __  
  / ___// /_  ___  / / /  / /   (_)___  / /__
  \__ \/ __ \/ _ \/ / /  / /   / / __ \/ //_/
 ___/ / / / /  __/ / /  / /___/ / / / / ,<   
/____/_/ /_/\___/_/_/  /_____/_/_/ /_/_/|_|  
                                              
EOF
    echo -e "${DIM}  SSH Bootstrap System — github.com/EpicSprout/ShellLink${RESET}"
    echo -e "${DIM}  ─────────────────────────────────────────────────────${RESET}"
    echo ""
}

# ── Section Header ───────────────────────────────────────────
header() {
    echo ""
    echo -e "${MAGENTA}${BOLD}  ┌─────────────────────────────────────────────┐${RESET}"
    echo -e "${MAGENTA}${BOLD}  │  $*$(printf '%*s' $((42 - ${#1})) '')│${RESET}"
    echo -e "${MAGENTA}${BOLD}  └─────────────────────────────────────────────┘${RESET}"
    echo ""
}

# ── Prompt helpers ───────────────────────────────────────────
prompt_value() {
    local prompt="$1"
    local default="${2:-}"
    local value

    if [[ -n "$default" ]]; then
        echo -en "${YELLOW}  ?${RESET}  ${prompt} [${default}]: "
    else
        echo -en "${YELLOW}  ?${RESET}  ${prompt}: "
    fi
    read -r value
    echo "${value:-$default}"
}

prompt_secret() {
    local prompt="$1"
    local value
    echo -en "${YELLOW}  ?${RESET}  ${prompt}: "
    read -rs value
    echo ""
    echo "$value"
}

# ── OS detection ─────────────────────────────────────────────
detect_os() {
    case "$OSTYPE" in
        darwin*)  echo "macos" ;;
        linux*)   echo "linux" ;;
        msys*|cygwin*|mingw*) echo "windows" ;;
        *)        echo "unknown" ;;
    esac
}

# ── Cleanup trap helper ─────────────────────────────────────
# Usage: register_cleanup "command to run"
_CLEANUP_COMMANDS=()
_run_cleanup() {
    for cmd in "${_CLEANUP_COMMANDS[@]}"; do
        eval "$cmd" 2>/dev/null || true
    done
}
trap _run_cleanup EXIT

register_cleanup() {
    _CLEANUP_COMMANDS+=("$1")
}
