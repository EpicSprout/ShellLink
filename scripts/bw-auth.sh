#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║              ShellLink — Bitwarden Auth (Bash)               ║
# ║              Login, unlock, and retrieve SSH keys             ║
# ╚══════════════════════════════════════════════════════════════╝
set -euo pipefail

# Source common utilities if not already loaded
if ! declare -f info &>/dev/null; then
    source "$(dirname "$0")/common.sh"
fi

# ── Login to Bitwarden ───────────────────────────────────────
bw_login() {
    header "Bitwarden Authentication"

    # Check current status
    local status
    status=$(bw status 2>/dev/null | jq -r '.status' 2>/dev/null || echo "unauthenticated")

    if [[ "$status" == "unlocked" ]]; then
        info "Vault is already unlocked"
        # Get session key for this shell
        BW_SESSION=$(bw unlock --raw 2>/dev/null || true)
        if [[ -n "${BW_SESSION:-}" ]]; then
            export BW_SESSION
            return 0
        fi
    fi

    if [[ "$status" == "unauthenticated" ]]; then
        step "Logging in to Bitwarden..."

        # Check for API key environment variables
        if [[ -z "${BW_CLIENTID:-}" ]]; then
            BW_CLIENTID=$(prompt_value "Enter BW_CLIENTID (Bitwarden API client ID)")
            [[ -z "$BW_CLIENTID" ]] && die "BW_CLIENTID is required"
            export BW_CLIENTID
        else
            info "Using BW_CLIENTID from environment"
        fi

        if [[ -z "${BW_CLIENTSECRET:-}" ]]; then
            BW_CLIENTSECRET=$(prompt_secret "Enter BW_CLIENTSECRET (Bitwarden API client secret)")
            [[ -z "$BW_CLIENTSECRET" ]] && die "BW_CLIENTSECRET is required"
            export BW_CLIENTSECRET
        else
            info "Using BW_CLIENTSECRET from environment"
        fi

        bw login --apikey
        success "Logged in to Bitwarden"
    elif [[ "$status" == "locked" ]]; then
        info "Already logged in, vault is locked"
    fi

    # Unlock the vault
    step "Unlocking vault..."
    local master_password
    master_password=$(prompt_secret "Enter your Bitwarden master password")
    [[ -z "$master_password" ]] && die "Master password is required"

    BW_SESSION=$(echo "$master_password" | bw unlock --raw 2>/dev/null) || die "Failed to unlock vault. Check your master password."
    export BW_SESSION

    # Clear the password from memory
    master_password=""

    success "Vault unlocked"
}

# ── Retrieve SSH key from Bitwarden ──────────────────────────
# Supports multiple storage methods:
#   1. Secure Note with key in the "notes" field
#   2. Custom field named "private-key"
#   3. Attachment on the item
bw_get_ssh_key() {
    local item_name="${1:-ssh-key}"

    header "Retrieving SSH Key"
    step "Looking for item: ${item_name}"

    # Sync vault first
    bw sync --session "$BW_SESSION" &>/dev/null || warn "Sync skipped (may be offline)"

    # Get the item
    local item
    item=$(bw get item "$item_name" --session "$BW_SESSION" 2>/dev/null) || die "Item '${item_name}' not found in Bitwarden vault"

    local key_data=""

    # Method 1: Check notes field (Secure Note)
    local notes
    notes=$(echo "$item" | jq -r '.notes // empty' 2>/dev/null)
    if [[ -n "$notes" && "$notes" == *"BEGIN"*"KEY"* ]]; then
        key_data="$notes"
        info "Found SSH key in notes field"
    fi

    # Method 2: Check custom fields
    if [[ -z "$key_data" ]]; then
        local field_value
        field_value=$(echo "$item" | jq -r '.fields[]? | select(.name == "private-key" or .name == "private_key" or .name == "ssh-key" or .name == "ssh_key") | .value // empty' 2>/dev/null)
        if [[ -n "$field_value" && "$field_value" == *"BEGIN"*"KEY"* ]]; then
            key_data="$field_value"
            info "Found SSH key in custom field"
        fi
    fi

    # Method 3: Check attachments
    if [[ -z "$key_data" ]]; then
        local item_id
        item_id=$(echo "$item" | jq -r '.id')
        local attachment_id
        attachment_id=$(echo "$item" | jq -r '.attachments[]? | select(.fileName == "id_ed25519" or .fileName == "id_rsa" or .fileName == "ssh_key" or (.fileName | test("key$"; "i"))) | .id' 2>/dev/null | head -1)

        if [[ -n "$attachment_id" ]]; then
            key_data=$(bw get attachment "$attachment_id" --itemid "$item_id" --session "$BW_SESSION" --raw 2>/dev/null)
            info "Found SSH key as attachment"
        fi
    fi

    if [[ -z "$key_data" ]]; then
        die "No SSH key found in Bitwarden item '${item_name}'. Store it as:\n  1. A Secure Note with the key in the notes field\n  2. A custom field named 'private-key'\n  3. An attachment named 'id_ed25519'"
    fi

    # Ensure proper line endings and trailing newline
    key_data=$(echo "$key_data" | sed 's/\r$//')
    if [[ "${key_data: -1}" != $'\n' ]]; then
        key_data="${key_data}"$'\n'
    fi

    echo "$key_data"
}

# ── Retrieve multiple SSH keys ───────────────────────────────
bw_get_ssh_keys() {
    local search_term="${1:-ssh-key}"

    header "Searching for SSH Keys"
    step "Searching for items matching: ${search_term}"

    bw sync --session "$BW_SESSION" &>/dev/null || warn "Sync skipped"

    local items
    items=$(bw list items --search "$search_term" --session "$BW_SESSION" 2>/dev/null) || die "Failed to search vault"

    local count
    count=$(echo "$items" | jq 'length')

    if [[ "$count" -eq 0 ]]; then
        die "No items matching '${search_term}' found in vault"
    fi

    info "Found ${count} item(s) matching '${search_term}'"
    echo "$items"
}
