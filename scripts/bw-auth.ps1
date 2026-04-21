# ╔══════════════════════════════════════════════════════════════╗
# ║              ShellLink — Bitwarden Auth (PowerShell)         ║
# ║              Login, unlock, and retrieve SSH keys             ║
# ╚══════════════════════════════════════════════════════════════╝

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\common.ps1"

# ── Login to Bitwarden ───────────────────────────────────────
function Connect-Bitwarden {
    Show-ShellLinkHeader "Bitwarden Authentication"

    # Prevent first-run bw warning about missing config directory.
    $bwConfigDir = Join-Path $env:APPDATA "Bitwarden CLI"
    if (!(Test-Path $bwConfigDir)) {
        New-Item -ItemType Directory -Path $bwConfigDir -Force | Out-Null
    }

    # Check current status
    $statusRaw = & bw status 2>$null
    $statusJson = $null
    if ($statusRaw) {
        $statusJson = $statusRaw | ConvertFrom-Json -ErrorAction SilentlyContinue
    }
    $status = if ($statusJson) { $statusJson.status } else { "unauthenticated" }

    if ($status -eq "unlocked") {
        Write-ShellLinkInfo "Vault is already unlocked"
        return
    }

    if ($status -eq "unauthenticated") {
        Write-ShellLinkStep "Logging in to Bitwarden..."

        # Check for API key environment variables
        if (-not $env:BW_CLIENTID) {
            $env:BW_CLIENTID = Read-ShellLinkValue "Enter BW_CLIENTID (Bitwarden API client ID)"
            if ([string]::IsNullOrWhiteSpace($env:BW_CLIENTID)) {
                Exit-WithError "BW_CLIENTID is required"
            }
        } else {
            Write-ShellLinkInfo "Using BW_CLIENTID from environment"
        }

        if (-not $env:BW_CLIENTSECRET) {
            $env:BW_CLIENTSECRET = Read-ShellLinkSecret "Enter BW_CLIENTSECRET (Bitwarden API client secret)"
            if ([string]::IsNullOrWhiteSpace($env:BW_CLIENTSECRET)) {
                Exit-WithError "BW_CLIENTSECRET is required"
            }
        } else {
            Write-ShellLinkInfo "Using BW_CLIENTSECRET from environment"
        }

        & bw login --apikey
        if ($LASTEXITCODE -ne 0) { Exit-WithError "Bitwarden login failed" }
        Write-ShellLinkSuccess "Logged in to Bitwarden"
    } elseif ($status -eq "locked") {
        Write-ShellLinkInfo "Already logged in, vault is locked"
    }

    # Unlock the vault
    Write-ShellLinkStep "Unlocking vault..."
    $masterPassword = Read-ShellLinkSecret "Enter your Bitwarden master password"
    if ([string]::IsNullOrWhiteSpace($masterPassword)) {
        Exit-WithError "Master password is required"
    }

    $env:BW_PASSWORD = $masterPassword
    try {
        $script:BwSession = & bw unlock --raw --passwordenv BW_PASSWORD 2>$null
    } finally {
        Remove-Item Env:BW_PASSWORD -ErrorAction SilentlyContinue
    }
    if ($LASTEXITCODE -ne 0 -or -not $script:BwSession) {
        Exit-WithError "Failed to unlock vault. Check your master password."
    }
    $env:BW_SESSION = $script:BwSession

    # Clear password from memory
    $masterPassword = $null
    [GC]::Collect()

    Write-ShellLinkSuccess "Vault unlocked"
}

# ── Retrieve SSH key from Bitwarden ──────────────────────────
function Get-SSHKeyFromVault {
    param(
        [string]$ItemName = "ssh-key"
    )

    Show-ShellLinkHeader "Retrieving SSH Key"
    Write-ShellLinkStep "Looking for item: $ItemName"

    # Sync vault
    & bw sync --session $script:BwSession 2>$null | Out-Null

    # Get the item
    $itemJson = & bw get item $ItemName --session $script:BwSession 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $itemJson) {
        Exit-WithError "Item '$ItemName' not found in Bitwarden vault"
    }

    $item = $itemJson | ConvertFrom-Json
    $keyData = $null

    # Method 1: Check notes field (Secure Note)
    if ($item.notes -and $item.notes -match "BEGIN.*KEY") {
        $keyData = $item.notes
        Write-ShellLinkInfo "Found SSH key in notes field"
    }

    # Method 2: Check custom fields
    if (-not $keyData -and $item.fields) {
        $keyField = $item.fields | Where-Object {
            $_.name -in @("private-key", "private_key", "ssh-key", "ssh_key")
        } | Select-Object -First 1

        if ($keyField -and $keyField.value -match "BEGIN.*KEY") {
            $keyData = $keyField.value
            Write-ShellLinkInfo "Found SSH key in custom field"
        }
    }

    # Method 3: Check attachments
    if (-not $keyData -and $item.attachments) {
        $attachment = $item.attachments | Where-Object {
            $_.fileName -in @("id_ed25519", "id_rsa", "ssh_key") -or $_.fileName -match "key$"
        } | Select-Object -First 1

        if ($attachment) {
            $keyData = & bw get attachment $attachment.id --itemid $item.id --session $script:BwSession --raw 2>$null
            Write-ShellLinkInfo "Found SSH key as attachment"
        }
    }

    if (-not $keyData) {
        Exit-WithError @"
No SSH key found in Bitwarden item '$ItemName'. Store it as:
  1. A Secure Note with the key in the notes field
  2. A custom field named 'private-key'
  3. An attachment named 'id_ed25519'
"@
    }

    # Normalize line endings
    $keyData = $keyData -replace "`r`n", "`n"
    if (-not $keyData.EndsWith("`n")) {
        $keyData += "`n"
    }

    return $keyData
}
