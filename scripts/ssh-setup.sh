#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║              ShellLink — SSH Setup (Bash)                    ║
# ║              Agent, keys, and config management              ║
# ╚══════════════════════════════════════════════════════════════╝
set -euo pipefail

# Source common utilities if not already loaded
if ! declare -f info &>/dev/null; then
    source "$(dirname "$0")/common.sh"
fi

SSH_DIR="$HOME/.ssh"
SSH_CONFIG_DIR="$HOME/.ssh-config"
REPO_URL="${SHELLLINK_REPO:-https://github.com/EpicSprout/ShellLink.git}"

# ── Ensure ~/.ssh directory ──────────────────────────────────
ensure_ssh_dir() {
    if [[ ! -d "$SSH_DIR" ]]; then
        step "Creating ~/.ssh directory..."
        mkdir -p "$SSH_DIR"
    fi
    chmod 700 "$SSH_DIR"
    success "~/.ssh directory ready"
}

# ── Start ssh-agent ──────────────────────────────────────────
start_ssh_agent() {
    header "SSH Agent"

    # Check if agent is already running
    if [[ -n "${SSH_AUTH_SOCK:-}" ]] && ssh-add -l &>/dev/null; then
        info "ssh-agent is already running"
        return 0
    fi

    # Check if agent is running but we lost the socket
    if [[ -n "${SSH_AGENT_PID:-}" ]] && kill -0 "$SSH_AGENT_PID" 2>/dev/null; then
        info "ssh-agent is running (PID: $SSH_AGENT_PID)"
        return 0
    fi

    step "Starting ssh-agent..."

    # macOS uses Keychain integration
    if [[ "$(detect_os)" == "macos" ]]; then
        # macOS ssh-agent is managed by launchd
        if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
            eval "$(ssh-agent -s)" >/dev/null
        fi
        success "ssh-agent started (macOS Keychain integration)"
        return 0
    fi

    # Linux: Check for systemd user service
    if command -v systemctl &>/dev/null && systemctl --user is-active ssh-agent &>/dev/null; then
        info "ssh-agent managed by systemd"
        export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR}/ssh-agent.socket"
        return 0
    fi

    # Start agent manually
    eval "$(ssh-agent -s)" >/dev/null
    success "ssh-agent started (PID: $SSH_AGENT_PID)"

    # Add agent startup to shell profile if not already there
    add_agent_to_profile
}

# ── Add agent startup to shell profile ───────────────────────
add_agent_to_profile() {
    local shell_rc=""
    if [[ -n "${ZSH_VERSION:-}" || "$SHELL" == *"zsh"* ]]; then
        shell_rc="$HOME/.zshrc"
    elif [[ -n "${BASH_VERSION:-}" || "$SHELL" == *"bash"* ]]; then
        shell_rc="$HOME/.bashrc"
    fi

    if [[ -z "$shell_rc" ]]; then
        warn "Could not detect shell profile. Add ssh-agent startup manually."
        return 0
    fi

    local marker="# ShellLink ssh-agent"
    if [[ -f "$shell_rc" ]] && grep -q "$marker" "$shell_rc" 2>/dev/null; then
        return 0
    fi

    step "Adding ssh-agent auto-start to $(basename "$shell_rc")..."
    cat >> "$shell_rc" << 'AGENT_EOF'

# ShellLink ssh-agent — auto-start
if [ -z "$SSH_AUTH_SOCK" ]; then
    eval "$(ssh-agent -s)" >/dev/null 2>&1
fi
AGENT_EOF

    success "Added ssh-agent auto-start to $(basename "$shell_rc")"
}

# ── Write SSH key to disk ────────────────────────────────────
write_ssh_key() {
    local key_data="$1"
    local key_name="${2:-id_ed25519}"
    local key_path="$SSH_DIR/$key_name"

    header "Installing SSH Key"

    # Detect key type
    local key_type="unknown"
    if echo "$key_data" | grep -q "ed25519"; then
        key_type="ed25519"
    elif echo "$key_data" | grep -q "RSA"; then
        key_type="RSA"
    elif echo "$key_data" | grep -q "ECDSA\|ecdsa"; then
        key_type="ECDSA"
    fi
    info "Key type detected: $key_type"

    # Check if key already exists
    if [[ -f "$key_path" ]]; then
        local existing_fingerprint new_fingerprint

        existing_fingerprint=$(ssh-keygen -lf "$key_path" 2>/dev/null | awk '{print $2}' || echo "unknown")

        # Write to temp to compare
        local tmp_key
        tmp_key=$(mktemp)
        register_cleanup "rm -f '$tmp_key'"
        echo "$key_data" > "$tmp_key"
        chmod 600 "$tmp_key"

        new_fingerprint=$(ssh-keygen -lf "$tmp_key" 2>/dev/null | awk '{print $2}' || echo "new")
        rm -f "$tmp_key"

        if [[ "$existing_fingerprint" == "$new_fingerprint" ]]; then
            info "SSH key already installed (fingerprint matches)"
            success "Key: $key_path"
            return 0
        else
            warn "Different SSH key exists at $key_path"
            local overwrite
            overwrite=$(prompt_value "Overwrite existing key? (y/N)" "N")
            if [[ "${overwrite,,}" != "y" ]]; then
                # Use alternative name
                key_name="${key_name}_shelllink"
                key_path="$SSH_DIR/$key_name"
                info "Saving as $key_path instead"
            fi
        fi
    fi

    # Write the key
    step "Writing SSH key to $key_path..."
    echo "$key_data" > "$key_path"
    chmod 600 "$key_path"
    success "SSH key installed: $key_path"

    # Generate public key if it doesn't exist
    if [[ ! -f "${key_path}.pub" ]]; then
        step "Generating public key..."
        ssh-keygen -y -f "$key_path" > "${key_path}.pub" 2>/dev/null || warn "Could not generate public key"
        if [[ -f "${key_path}.pub" ]]; then
            chmod 644 "${key_path}.pub"
            success "Public key: ${key_path}.pub"
        fi
    fi

    echo "$key_path"
}

# ── Load key into ssh-agent ──────────────────────────────────
load_key_to_agent() {
    local key_path="$1"

    step "Adding key to ssh-agent..."

    # Check if key is already loaded
    local key_fingerprint
    key_fingerprint=$(ssh-keygen -lf "$key_path" 2>/dev/null | awk '{print $2}' || echo "")

    if [[ -n "$key_fingerprint" ]] && ssh-add -l 2>/dev/null | grep -q "$key_fingerprint"; then
        info "Key already loaded in ssh-agent"
        return 0
    fi

    if [[ "$(detect_os)" == "macos" ]]; then
        # macOS: use Keychain
        ssh-add --apple-use-keychain "$key_path" 2>/dev/null || ssh-add "$key_path"
    else
        ssh-add "$key_path"
    fi

    success "Key loaded into ssh-agent"
}

# ── Sync SSH config from repo ────────────────────────────────
sync_ssh_config() {
    header "SSH Config"

    # Clone or update the config repo
    if [[ -d "$SSH_CONFIG_DIR" ]]; then
        step "Updating SSH config from repo..."
        (cd "$SSH_CONFIG_DIR" && git pull --quiet 2>/dev/null) || warn "Could not update repo (may be offline)"
    else
        step "Cloning SSH config repo..."
        git clone --quiet "$REPO_URL" "$SSH_CONFIG_DIR" 2>/dev/null || die "Failed to clone ShellLink repo"
    fi

    # Build config from template + .env
    local template_file="$SSH_CONFIG_DIR/ssh-config/config.template"
    local env_file="$SSH_CONFIG_DIR/ssh-config/.env"
    local source_config="$SSH_CONFIG_DIR/ssh-config/config"
    local target_config="$SSH_DIR/config"

    if [[ ! -f "$template_file" ]]; then
        warn "No ssh-config/config.template found in repo, skipping"
        return 0
    fi

    if [[ ! -f "$env_file" ]]; then
        warn "No ssh-config/.env found — copy .env.example to .env and fill in your values"
        return 0
    fi

    # Parse .env: collect HOST_<alias>_<PROP>=value into associative arrays
    declare -A host_props
    declare -a host_aliases=()
    local seen_aliases=""

    while IFS= read -r line; do
        line=$(echo "$line" | xargs)
        [[ -z "$line" || "$line" == \#* ]] && continue
        if [[ "$line" =~ ^HOST_([^_]+)_([A-Z_]+)=(.*)$ ]]; then
            local alias="${BASH_REMATCH[1],,}"  # lowercase
            local prop="${BASH_REMATCH[2]}"
            local val="${BASH_REMATCH[3]}"
            val=$(echo "$val" | xargs)
            host_props["${alias}__${prop}"]="$val"
            # Track unique aliases in order
            if [[ "$seen_aliases" != *"|${alias}|"* ]]; then
                host_aliases+=("$alias")
                seen_aliases="${seen_aliases}|${alias}|"
            fi
        fi
    done < "$env_file"

    if [[ ${#host_aliases[@]} -eq 0 ]]; then
        warn "No HOST_ entries found in .env — nothing to generate"
        return 0
    fi

    # Start with template (global defaults)
    local config_content
    config_content=$(cat "$template_file")

    # Append each host block
    for alias in $(printf '%s\n' "${host_aliases[@]}" | sort); do
        local hostname="${host_props["${alias}__HOSTNAME"]:-}"
        if [[ -z "$hostname" ]]; then
            warn "HOST_${alias}: missing HOSTNAME, skipping"
            continue
        fi

        local label="${host_props["${alias}__LABEL"]:-$alias}"
        local port="${host_props["${alias}__PORT"]:-22}"
        local id_file="${host_props["${alias}__IDENTITY_FILE"]:-~/.ssh/id_ed25519}"
        local user="${host_props["${alias}__USER"]:-}"

        config_content+=$'\n\n\n'"# ── ${label} ──"
        config_content+=$'\n'"Host ${alias}"
        config_content+=$'\n'"    HostName ${hostname}"
        if [[ -n "$user" ]]; then
            config_content+=$'\n'"    User ${user}"
        fi
        config_content+=$'\n'"    IdentityFile ${id_file}"
        config_content+=$'\n'"    Port ${port}"
    done

    # Write generated config
    echo "$config_content" > "$source_config"
    success "Generated ssh-config/config (${#host_aliases[@]} host(s))"

    if [[ -L "$target_config" ]]; then
        local current_target
        current_target=$(readlink "$target_config")
        if [[ "$current_target" == "$source_config" ]]; then
            info "SSH config symlink already correct"
            return 0
        fi
        rm -f "$target_config"
    elif [[ -f "$target_config" ]]; then
        warn "Existing ~/.ssh/config found"
        local backup="$target_config.backup.$(date +%Y%m%d%H%M%S)"
        cp "$target_config" "$backup"
        info "Backed up to $backup"
        rm -f "$target_config"
    fi

    ln -sf "$source_config" "$target_config"
    chmod 600 "$target_config" 2>/dev/null || true
    success "SSH config linked: $target_config → $source_config"
}

# ── Load key directly into agent without writing to disk ─────
load_key_to_agent_memory() {
    local key_data="$1"

    step "Loading SSH key directly into ssh-agent (no disk write)..."

    # ssh-add can read from stdin with - on some systems
    if echo "$key_data" | ssh-add - 2>/dev/null; then
        success "Key loaded into ssh-agent (memory only — not written to disk)"
        return 0
    fi

    # Fallback: write to temp file, load, then securely delete
    local tmp_key
    tmp_key=$(mktemp)
    echo "$key_data" > "$tmp_key"
    chmod 600 "$tmp_key"

    ssh-add "$tmp_key" 2>/dev/null
    local result=$?

    # Securely remove the temp file
    if command -v shred &>/dev/null; then
        shred -u "$tmp_key"
    else
        rm -f "$tmp_key"
    fi

    if [[ $result -eq 0 ]]; then
        success "Key loaded into ssh-agent (temp file securely removed)"
    else
        die "Failed to load key into ssh-agent"
    fi
}
