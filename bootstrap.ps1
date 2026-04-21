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
#   iwr https://raw.githubusercontent.com/EpicSprout/ShellLink/main/bootstrap.ps1 | iex
#
# ENVIRONMENT VARIABLES:
#   BW_CLIENTID      - Bitwarden API client ID
#   BW_CLIENTSECRET  - Bitwarden API client secret
#   SHELLLINK_KEY    - Bitwarden item name for SSH key (default: "ssh-key")
#   SHELLLINK_MODE   - "agent" (load to agent only) or "disk" (write to disk + agent)
#   SHELLLINK_REPO   - Custom repo URL (default: EpicSprout/ShellLink)

param(
    [string]$Key = "",
    [switch]$AgentOnly,
    [switch]$SkipConfig,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

# -- Help -----------------------------------------------------
if ($Help) {
    Write-Host @"

ShellLink - SSH Bootstrap System

Usage: bootstrap.ps1 [OPTIONS]

Options:
  -Key NAME         Bitwarden item name for SSH key (default: ssh-key)
  -AgentOnly        Load key into ssh-agent only (no disk write)
  -SkipConfig       Skip SSH config sync
  -Help             Show this help

Environment Variables:
  BW_CLIENTID       Bitwarden API client ID
  BW_CLIENTSECRET   Bitwarden API client secret
  SHELLLINK_KEY     Same as -Key
  SHELLLINK_MODE    'agent' or 'disk'
  SHELLLINK_REPO    Custom repo URL

"@
    return
}

# -- Determine script location / temp clone -------------------
$ShellLinkDir = ""
$TempClone = ""

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { $PWD.Path }
$commonPath = Join-Path $scriptDir "scripts\common.ps1"

if (Test-Path $commonPath) {
    $ShellLinkDir = $scriptDir
} elseif (Test-Path "$env:USERPROFILE\.ssh-config\scripts\common.ps1") {
    $ShellLinkDir = "$env:USERPROFILE\.ssh-config"
} else {
    # Bootstrapping from iwr | iex - clone to temp
    $TempClone = Join-Path $env:TEMP "ShellLink_$(Get-Random)"
    $ShellLinkDir = $TempClone

    $repoUrl = if ($env:SHELLLINK_REPO) { $env:SHELLLINK_REPO } else { "https://github.com/EpicSprout/ShellLink.git" }

    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) {
        Write-Host "Git is required. Attempting to install..." -ForegroundColor Yellow
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if ($winget) {
            & winget install Git.Git --accept-package-agreements --accept-source-agreements
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        } else {
            Write-Host "ERROR: Cannot install git. Install from https://git-scm.com/ and re-run." -ForegroundColor Red
            return
        }
    }

    & git clone --quiet $repoUrl $TempClone 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to clone ShellLink repo." -ForegroundColor Red
        return
    }
}

# Source all modules
. "$ShellLinkDir\scripts\common.ps1"
. "$ShellLinkDir\scripts\bw-auth.ps1"
. "$ShellLinkDir\scripts\ssh-setup.ps1"

# -- Resolve parameters ---------------------------------------
$ItemName = if ($Key) { $Key } elseif ($env:SHELLLINK_KEY) { $env:SHELLLINK_KEY } else { "ssh-key" }
$Mode = if ($AgentOnly) { "agent" } elseif ($env:SHELLLINK_MODE) { $env:SHELLLINK_MODE } else { "disk" }

# -- Main Bootstrap Flow --------------------------------------
function Start-ShellLink {
    Show-ShellLinkBanner

    $startTime = Get-Date

    try {
        # Phase 1: Install dependencies
        . "$ShellLinkDir\scripts\install.ps1"
        Install-Dependencies

        # Phase 2: Ensure SSH directory and agent
        Ensure-SSHDirectory
        Start-SSHAgentService

        # Phase 3: Bitwarden auth + key retrieval
        Connect-Bitwarden
        $keyData = Get-SSHKeyFromVault -ItemName $ItemName

        # Phase 4: Install the key
        if ($Mode -eq "agent") {
            # On Windows, ssh-add doesn't easily support stdin
            # Write to temp, load, then remove
            $tmpKey = [IO.Path]::GetTempFileName()
            try {
                $keyData | Set-Content -Path $tmpKey -NoNewline -Encoding ascii
                # Set restrictive permissions
                $acl = New-Object System.Security.AccessControl.FileSecurity
                $acl.SetAccessRuleProtection($true, $false)
                $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
                $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    $currentUser, "Read", "None", "None", "Allow"
                )
                $acl.AddAccessRule($rule)
                Set-Acl -Path $tmpKey -AclObject $acl

                & ssh-add $tmpKey
                Write-ShellLinkSuccess "Key loaded into ssh-agent (memory only)"
            } finally {
                # Securely remove
                if (Test-Path $tmpKey) {
                    # Overwrite with random data before deleting
                    $randomBytes = New-Object byte[] (Get-Item $tmpKey).Length
                    [Security.Cryptography.RandomNumberGenerator]::Fill($randomBytes)
                    [IO.File]::WriteAllBytes($tmpKey, $randomBytes)
                    Remove-Item $tmpKey -Force
                }
            }
        } else {
            $keyPath = Write-SSHKey -KeyData $keyData -KeyName "id_ed25519"
            Add-SSHKeyToAgent -KeyPath $keyPath
        }

        # Phase 5: SSH config
        if (-not $SkipConfig) {
            Sync-SSHConfig
        }

        # -- Done ---------------------------------------------
        $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds)

        Write-Host ""
        Write-Host "  +==================================================+" -ForegroundColor Green
        Write-Host "  |                                                  |" -ForegroundColor Green
        Write-Host "  |        ShellLink setup complete!                 |" -ForegroundColor Green
        Write-Host "  |                                                  |" -ForegroundColor Green
        Write-Host "  +==================================================+" -ForegroundColor Green
        Write-Host ""

        Write-ShellLinkInfo "Completed in ${elapsed}s"
        Write-Host ""

        # Show loaded keys
        Write-ShellLinkStep "Loaded SSH keys:"
        $keys = & ssh-add -l 2>$null
        if ($LASTEXITCODE -eq 0 -and $keys) {
            $keys | ForEach-Object { Write-Host "    $_" }
        } else {
            Write-Host "    (none)"
        }
        Write-Host ""

        # Show config info
        $configPath = Join-Path $SSHDir "config"
        if (-not $SkipConfig -and (Test-Path $configPath)) {
            Write-ShellLinkStep "Available SSH hosts:"
            Get-Content $configPath | Where-Object { $_ -match "^Host\s" -and $_ -notmatch "\*" } | ForEach-Object {
                $hostName = ($_ -replace "^Host\s+", "").Trim()
                Write-Host "    -> $hostName"
            }
            Write-Host ""
        }

        Write-ShellLinkSuccess "You're ready to go! Try: ssh <hostname>"
        Write-Host ""

    } finally {
        # Clean up temp clone
        if ($TempClone -and (Test-Path $TempClone)) {
            Remove-Item $TempClone -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Start-ShellLink
