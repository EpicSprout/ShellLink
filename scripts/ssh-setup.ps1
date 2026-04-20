# ╔══════════════════════════════════════════════════════════════╗
# ║              ShellLink — SSH Setup (PowerShell)              ║
# ║              Agent, keys, and config management              ║
# ╚══════════════════════════════════════════════════════════════╝

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\common.ps1"

$SSHDir = "$env:USERPROFILE\.ssh"
$SSHConfigDir = "$env:USERPROFILE\.ssh-config"
$RepoUrl = if ($env:SHELLLINK_REPO) { $env:SHELLLINK_REPO } else { "https://github.com/EpicSprout/ShellLink.git" }

# ── Ensure ~/.ssh directory ──────────────────────────────────
function Ensure-SSHDirectory {
    if (!(Test-Path $SSHDir)) {
        Write-ShellLinkStep "Creating ~/.ssh directory..."
        New-Item -ItemType Directory -Path $SSHDir -Force | Out-Null
    }

    # Set restrictive permissions on Windows
    $acl = Get-Acl $SSHDir
    $acl.SetAccessRuleProtection($true, $false)
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $currentUser, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
    )
    $acl.AddAccessRule($rule)
    Set-Acl -Path $SSHDir -AclObject $acl -ErrorAction SilentlyContinue

    Write-ShellLinkSuccess "~/.ssh directory ready"
}

# ── Start ssh-agent service ──────────────────────────────────
function Start-SSHAgentService {
    Show-ShellLinkHeader "SSH Agent"

    # Check if ssh-agent service exists
    $service = Get-Service ssh-agent -ErrorAction SilentlyContinue
    if (-not $service) {
        Write-ShellLinkWarn "OpenSSH Authentication Agent service not found"
        Write-ShellLinkWarn "Install OpenSSH via Settings > Apps > Optional Features"

        # Try starting manually in current session
        $sshAgent = Get-Command ssh-agent -ErrorAction SilentlyContinue
        if ($sshAgent) {
            Write-ShellLinkStep "Starting ssh-agent for this session..."
            $agentOutput = & ssh-agent
            if ($agentOutput -match "SSH_AUTH_SOCK=(.+?);") {
                $env:SSH_AUTH_SOCK = $Matches[1]
            }
            if ($agentOutput -match "SSH_AGENT_PID=(\d+)") {
                $env:SSH_AGENT_PID = $Matches[1]
            }
            Write-ShellLinkSuccess "ssh-agent started for this session"
        }
        return
    }

    if ($service.Status -ne "Running") {
        Write-ShellLinkStep "Starting SSH Agent service..."
        if (Test-IsAdmin) {
            Set-Service -Name ssh-agent -StartupType Automatic
            Start-Service ssh-agent
            Write-ShellLinkSuccess "SSH Agent service started and set to automatic"
        } else {
            Write-ShellLinkWarn "Run as Administrator to start SSH Agent service"
            Write-ShellLinkWarn "Or run: Set-Service -Name ssh-agent -StartupType Automatic; Start-Service ssh-agent"
            try {
                Start-Process powershell -ArgumentList "-Command", "Set-Service -Name ssh-agent -StartupType Automatic; Start-Service ssh-agent" -Verb RunAs -Wait
                Write-ShellLinkSuccess "SSH Agent service started (via elevation)"
            } catch {
                Write-ShellLinkWarn "Could not start SSH Agent service. Start it manually."
            }
        }
    } else {
        Write-ShellLinkInfo "SSH Agent service is running"
    }
}

# ── Write SSH key to disk ────────────────────────────────────
function Write-SSHKey {
    param(
        [string]$KeyData,
        [string]$KeyName = "id_ed25519"
    )

    Show-ShellLinkHeader "Installing SSH Key"

    $keyPath = Join-Path $SSHDir $KeyName

    # Detect key type
    $keyType = "unknown"
    if ($KeyData -match "ed25519") { $keyType = "ed25519" }
    elseif ($KeyData -match "RSA") { $keyType = "RSA" }
    elseif ($KeyData -match "ECDSA|ecdsa") { $keyType = "ECDSA" }
    Write-ShellLinkInfo "Key type detected: $keyType"

    # Check if key already exists
    if (Test-Path $keyPath) {
        $existingFingerprint = & ssh-keygen -lf $keyPath 2>$null
        if ($existingFingerprint) {
            $existingFp = ($existingFingerprint -split '\s+')[1]
        } else {
            $existingFp = "unknown"
        }

        # Write to temp to compare
        $tmpKey = [IO.Path]::GetTempFileName()
        try {
            $KeyData | Set-Content -Path $tmpKey -NoNewline -Encoding ascii
            $newFingerprint = & ssh-keygen -lf $tmpKey 2>$null
            $newFp = if ($newFingerprint) { ($newFingerprint -split '\s+')[1] } else { "new" }
        } finally {
            Remove-Item $tmpKey -Force -ErrorAction SilentlyContinue
        }

        if ($existingFp -eq $newFp) {
            Write-ShellLinkInfo "SSH key already installed (fingerprint matches)"
            Write-ShellLinkSuccess "Key: $keyPath"
            return $keyPath
        } else {
            Write-ShellLinkWarn "Different SSH key exists at $keyPath"
            $overwrite = Read-ShellLinkValue "Overwrite existing key? (y/N)" "N"
            if ($overwrite -ne "y") {
                $KeyName = "${KeyName}_shelllink"
                $keyPath = Join-Path $SSHDir $KeyName
                Write-ShellLinkInfo "Saving as $keyPath instead"
            }
        }
    }

    # Write the key
    Write-ShellLinkStep "Writing SSH key to $keyPath..."
    $KeyData | Set-Content -Path $keyPath -NoNewline -Encoding ascii

    # Set restrictive permissions (Windows equivalent of chmod 600)
    $acl = New-Object System.Security.AccessControl.FileSecurity
    $acl.SetAccessRuleProtection($true, $false)
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $currentUser, "Read,Write", "None", "None", "Allow"
    )
    $acl.AddAccessRule($rule)
    Set-Acl -Path $keyPath -AclObject $acl

    Write-ShellLinkSuccess "SSH key installed: $keyPath"

    # Generate public key
    $pubKeyPath = "$keyPath.pub"
    if (!(Test-Path $pubKeyPath)) {
        Write-ShellLinkStep "Generating public key..."
        $pubKey = & ssh-keygen -y -f $keyPath 2>$null
        if ($pubKey) {
            $pubKey | Set-Content -Path $pubKeyPath -Encoding ascii
            Write-ShellLinkSuccess "Public key: $pubKeyPath"
        }
    }

    return $keyPath
}

# ── Load key into ssh-agent ──────────────────────────────────
function Add-SSHKeyToAgent {
    param([string]$KeyPath)

    Write-ShellLinkStep "Adding key to ssh-agent..."

    # Check if key is already loaded
    $loaded = & ssh-add -l 2>$null
    if ($LASTEXITCODE -eq 0 -and $loaded) {
        $keyFp = & ssh-keygen -lf $KeyPath 2>$null
        if ($keyFp) {
            $fp = ($keyFp -split '\s+')[1]
            if ($loaded -match [regex]::Escape($fp)) {
                Write-ShellLinkInfo "Key already loaded in ssh-agent"
                return
            }
        }
    }

    & ssh-add $KeyPath
    if ($LASTEXITCODE -eq 0) {
        Write-ShellLinkSuccess "Key loaded into ssh-agent"
    } else {
        Write-ShellLinkWarn "Failed to add key to ssh-agent. Add manually: ssh-add $KeyPath"
    }
}

# ── Sync SSH config from repo ────────────────────────────────
function Sync-SSHConfig {
    Show-ShellLinkHeader "SSH Config"

    # Clone or update the config repo
    if (Test-Path $SSHConfigDir) {
        Write-ShellLinkStep "Updating SSH config from repo..."
        Push-Location $SSHConfigDir
        try {
            & git pull --quiet 2>$null | Out-Null
        } catch {
            Write-ShellLinkWarn "Could not update repo (may be offline)"
        }
        Pop-Location
    } else {
        Write-ShellLinkStep "Cloning SSH config repo..."
        & git clone --quiet $RepoUrl $SSHConfigDir 2>$null
        if ($LASTEXITCODE -ne 0) {
            Exit-WithError "Failed to clone ShellLink repo"
        }
    }

    # Copy the config (Windows doesn't support symlinks without admin)
    $sourceConfig = Join-Path $SSHConfigDir "ssh-config\config"
    $targetConfig = Join-Path $SSHDir "config"

    if (!(Test-Path $sourceConfig)) {
        Write-ShellLinkWarn "No ssh-config/config found in repo, skipping"
        return
    }

    if (Test-Path $targetConfig) {
        $existingContent = Get-Content $targetConfig -Raw -ErrorAction SilentlyContinue
        $newContent = Get-Content $sourceConfig -Raw

        if ($existingContent -eq $newContent) {
            Write-ShellLinkInfo "SSH config already up to date"
            return
        }

        # Check if it's a managed config
        if ($existingContent -and $existingContent -notmatch "ShellLink") {
            $backup = "$targetConfig.backup.$(Get-Date -Format 'yyyyMMddHHmmss')"
            Copy-Item $targetConfig $backup
            Write-ShellLinkInfo "Backed up existing config to $backup"
        }
    }

    Copy-Item $sourceConfig $targetConfig -Force
    Write-ShellLinkSuccess "SSH config installed: $targetConfig"
}
