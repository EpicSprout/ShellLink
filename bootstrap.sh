#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║                                                              ║
# ║                     S H E L L   L I N K                      ║
# ║                                                              ║
# ║         One-command SSH bootstrap for developers             ║
# ║         github.com/EpicSprout/ShellLink                      ║
# ║                                                              ║
# ╚══════════════════════════════════════════════════════════════╝
#
# USAGE:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/EpicSprout/ShellLink/main/bootstrap.sh)"
#
# ENVIRONMENT VARIABLES:
#   BW_CLIENTID      - Bitwarden API client ID
#   BW_CLIENTSECRET  - Bitwarden API client secret
#   SHELLLINK_KEY    - Bitwarden item name for SSH key (default: "ssh-key")
#   SHELLLINK_MODE   - "agent" (load to agent only) or "disk" (write to disk + agent)
#   SHELLLINK_REPO   - Custom repo URL (default: EpicSprout/ShellLink)
#
set -euo pipefail

# ── Determine script location / temp clone ───────────────────
SHELLLINK_DIR=""
TEMP_CLONE=""

if [[ -f "$(dirname "$0")/scripts/common.sh" ]]; then
    # Running from repo checkout
    SHELLLINK_DIR="$(cd "$(dirname "$0")" && pwd)"
elif [[ -d "$HOME/.ssh-config/scripts" ]]; then
    # Already cloned
    SHELLLINK_DIR="$HOME/.ssh-config"
else
    # Bootstrapping from curl — clone to temp
    TEMP_CLONE=$(mktemp -d)
    SHELLLINK_DIR="$TEMP_CLONE"

    REPO_URL="${SHELLLINK_REPO:-https://github.com/EpicSprout/ShellLink.git}"

    if ! command -v git &>/dev/null; then
        echo "Git is required. Installing..."
        if command -v apt-get &>/dev/null; then
            sudo apt-get update -qq && sudo apt-get install -y -qq git
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y git
        elif command -v pacman &>/dev/null; then
            sudo pacman -Sy --noconfirm git
        elif command -v brew &>/dev/null; then
            brew install git
        else
            echo "ERROR: Cannot install git. Install it manually and re-run."
            exit 1
        fi
    fi

    git clone --quiet "$REPO_URL" "$TEMP_CLONE"
fi

# Source all modules
source "$SHELLLINK_DIR/scripts/common.sh"
source "$SHELLLINK_DIR/scripts/bw-auth.sh"
source "$SHELLLINK_DIR/scripts/ssh-setup.sh"

# ── Cleanup temp clone on exit ───────────────────────────────
if [[ -n "$TEMP_CLONE" ]]; then
    register_cleanup "rm -rf '$TEMP_CLONE'"
fi

# ── Parse arguments ──────────────────────────────────────────
ITEM_NAME="${SHELLLINK_KEY:-ssh-key}"
MODE="${SHELLLINK_MODE:-disk}"
SKIP_CONFIG=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --key|-k)
            ITEM_NAME="$2"
            shift 2
            ;;
        --agent-only|-a)
            MODE="agent"
            shift
            ;;
        --disk|-d)
            MODE="disk"
            shift
            ;;
        --skip-config)
            SKIP_CONFIG=true
            shift
            ;;
        --help|-h)
            echo ""
            echo "ShellLink — SSH Bootstrap System"
            echo ""
            echo "Usage: bootstrap.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -k, --key NAME      Bitwarden item name for SSH key (default: ssh-key)"
            echo "  -a, --agent-only    Load key into ssh-agent only (no disk write)"
            echo "  -d, --disk          Write key to disk and load into agent (default)"
            echo "  --skip-config       Skip SSH config sync"
            echo "  -h, --help          Show this help"
            echo ""
            echo "Environment Variables:"
            echo "  BW_CLIENTID         Bitwarden API client ID"
            echo "  BW_CLIENTSECRET     Bitwarden API client secret"
            echo "  SHELLLINK_KEY       Same as --key"
            echo "  SHELLLINK_MODE      'agent' or 'disk'"
            echo "  SHELLLINK_REPO      Custom repo URL"
            echo ""
            exit 0
            ;;
        *)
            warn "Unknown option: $1"
            shift
            ;;
    esac
done

# ── Main Bootstrap Flow ─────────────────────────────────────
main() {
    banner

    local start_time
    start_time=$(date +%s)

    # Phase 1: Install dependencies
    source "$SHELLLINK_DIR/scripts/install.sh"
    install_all_deps

    # Phase 2: Ensure SSH directory and agent
    ensure_ssh_dir
    start_ssh_agent

    # Phase 3: Bitwarden auth + key retrieval
    bw_login
    local key_data
    key_data=$(bw_get_ssh_key "$ITEM_NAME")

    # Phase 4: Install the key
    if [[ "$MODE" == "agent" ]]; then
        load_key_to_agent_memory "$key_data"
    else
        local key_path
        key_path=$(write_ssh_key "$key_data")
        load_key_to_agent "$key_path"
    fi

    # Phase 5: SSH config
    if [[ "$SKIP_CONFIG" != "true" ]]; then
        sync_ssh_config
    fi

    # ── Done ─────────────────────────────────────────────────
    local elapsed=$(( $(date +%s) - start_time ))

    echo ""
    echo -e "${GREEN}${BOLD}"
    echo "  ╔══════════════════════════════════════════════════╗"
    echo "  ║                                                  ║"
    echo "  ║        ShellLink setup complete!                 ║"
    echo "  ║                                                  ║"
    echo "  ╚══════════════════════════════════════════════════╝"
    echo -e "${RESET}"

    info "Completed in ${elapsed}s"
    echo ""

    # Show loaded keys
    step "Loaded SSH keys:"
    ssh-add -l 2>/dev/null || echo "  (none)"
    echo ""

    # Show config info
    if [[ "$SKIP_CONFIG" != "true" && -f "$HOME/.ssh/config" ]]; then
        step "Available SSH hosts:"
        grep -E "^Host " "$HOME/.ssh/config" 2>/dev/null | grep -v "\*" | sed 's/Host /  → /' || echo "  (none configured)"
        echo ""
    fi

    success "You're ready to go! Try: ssh <hostname>"
    echo ""
}

main "$@"
