#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║              ShellLink — Dependency Installer                ║
# ║              Linux / macOS                                   ║
# ╚══════════════════════════════════════════════════════════════╝
set -euo pipefail

# Source common utilities if not already loaded
if ! declare -f info &>/dev/null; then
    source "$(dirname "$0")/common.sh"
fi

# ── Check & install Bitwarden CLI ────────────────────────────
install_bw_cli() {
    if command -v bw &>/dev/null; then
        local bw_version
        bw_version=$(bw --version 2>/dev/null || echo "unknown")
        info "Bitwarden CLI already installed (v${bw_version})"
        return 0
    fi

    step "Installing Bitwarden CLI..."

    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command -v brew &>/dev/null; then
            brew install bitwarden-cli
        else
            warn "Homebrew not found. Installing via npm..."
            install_bw_via_npm
        fi
    else
        # Linux — try snap, then npm, then direct download
        if command -v snap &>/dev/null; then
            sudo snap install bw
        elif command -v npm &>/dev/null; then
            npm install -g @bitwarden/cli
        else
            install_bw_direct_linux
        fi
    fi

    if command -v bw &>/dev/null; then
        success "Bitwarden CLI installed successfully"
    else
        die "Failed to install Bitwarden CLI. Install manually: https://bitwarden.com/help/cli/"
    fi
}

# ── Install via npm (fallback) ───────────────────────────────
install_bw_via_npm() {
    if ! command -v npm &>/dev/null; then
        if command -v node &>/dev/null; then
            die "Node.js found but npm missing. Install npm first."
        fi
        # Try installing Node.js
        if [[ "$OSTYPE" == "darwin"* ]]; then
            die "Install Node.js via: brew install node"
        else
            if command -v apt-get &>/dev/null; then
                step "Installing Node.js via apt..."
                sudo apt-get update -qq && sudo apt-get install -y -qq nodejs npm
            elif command -v dnf &>/dev/null; then
                step "Installing Node.js via dnf..."
                sudo dnf install -y nodejs npm
            elif command -v pacman &>/dev/null; then
                step "Installing Node.js via pacman..."
                sudo pacman -Sy --noconfirm nodejs npm
            else
                die "Cannot install Node.js automatically. Install manually."
            fi
        fi
    fi
    npm install -g @bitwarden/cli
}

# ── Direct download for Linux ────────────────────────────────
install_bw_direct_linux() {
    step "Downloading Bitwarden CLI binary..."
    local tmp_dir
    tmp_dir=$(mktemp -d)
    local arch
    arch=$(uname -m)

    local url="https://vault.bitwarden.com/download/?app=cli&platform=linux"

    if command -v curl &>/dev/null; then
        curl -fsSL "$url" -o "${tmp_dir}/bw.zip"
    elif command -v wget &>/dev/null; then
        wget -q "$url" -O "${tmp_dir}/bw.zip"
    else
        die "Neither curl nor wget available. Install one first."
    fi

    if command -v unzip &>/dev/null; then
        unzip -q "${tmp_dir}/bw.zip" -d "${tmp_dir}"
    else
        die "unzip not found. Install it: sudo apt install unzip"
    fi

    chmod +x "${tmp_dir}/bw"
    sudo mv "${tmp_dir}/bw" /usr/local/bin/bw
    rm -rf "${tmp_dir}"
}

# ── Ensure ssh-agent dependencies ────────────────────────────
ensure_ssh_tools() {
    if ! command -v ssh-agent &>/dev/null; then
        step "Installing OpenSSH client..."
        if command -v apt-get &>/dev/null; then
            sudo apt-get update -qq && sudo apt-get install -y -qq openssh-client
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y openssh-clients
        elif command -v pacman &>/dev/null; then
            sudo pacman -Sy --noconfirm openssh
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            info "OpenSSH is built into macOS"
        else
            die "Cannot install OpenSSH. Install manually."
        fi
    fi
    success "SSH tools available"
}

# ── Ensure git ───────────────────────────────────────────────
ensure_git() {
    if command -v git &>/dev/null; then
        info "Git already installed"
        return 0
    fi

    step "Installing git..."
    if command -v apt-get &>/dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y -qq git
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y git
    elif command -v pacman &>/dev/null; then
        sudo pacman -Sy --noconfirm git
    elif command -v brew &>/dev/null; then
        brew install git
    else
        die "Cannot install git automatically. Install manually."
    fi
    success "Git installed"
}

# ── Ensure jq (for JSON parsing) ────────────────────────────
ensure_jq() {
    if command -v jq &>/dev/null; then
        return 0
    fi

    step "Installing jq..."
    if command -v apt-get &>/dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y -qq jq
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y jq
    elif command -v pacman &>/dev/null; then
        sudo pacman -Sy --noconfirm jq
    elif command -v brew &>/dev/null; then
        brew install jq
    else
        die "Cannot install jq automatically. Install manually."
    fi
    success "jq installed"
}

# ── Main ─────────────────────────────────────────────────────
install_all_deps() {
    header "Installing Dependencies"
    ensure_git
    ensure_jq
    ensure_ssh_tools
    install_bw_cli
    success "All dependencies ready"
}

# Run only when executed directly, not when sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_all_deps "$@"
fi
