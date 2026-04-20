# ╔══════════════════════════════════════════════════════════════╗
# ║              ShellLink — Dependency Installer (Windows)      ║
# ╚══════════════════════════════════════════════════════════════╝

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\common.ps1"

# ── Install Bitwarden CLI ────────────────────────────────────
function Install-BitwardenCLI {
    $bwPath = Get-Command bw -ErrorAction SilentlyContinue
    if ($bwPath) {
        $version = & bw --version 2>$null
        Write-ShellLinkInfo "Bitwarden CLI already installed (v$version)"
        return
    }

    Write-ShellLinkStep "Installing Bitwarden CLI..."

    # Try winget first
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Write-ShellLinkStep "Installing via winget..."
        & winget install Bitwarden.CLI --accept-package-agreements --accept-source-agreements
        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

        if (Get-Command bw -ErrorAction SilentlyContinue) {
            Write-ShellLinkSuccess "Bitwarden CLI installed via winget"
            return
        }
    }

    # Try scoop
    $scoop = Get-Command scoop -ErrorAction SilentlyContinue
    if ($scoop) {
        Write-ShellLinkStep "Installing via scoop..."
        & scoop install bitwarden-cli
        if (Get-Command bw -ErrorAction SilentlyContinue) {
            Write-ShellLinkSuccess "Bitwarden CLI installed via scoop"
            return
        }
    }

    # Try npm
    $npm = Get-Command npm -ErrorAction SilentlyContinue
    if ($npm) {
        Write-ShellLinkStep "Installing via npm..."
        & npm install -g @bitwarden/cli
        if (Get-Command bw -ErrorAction SilentlyContinue) {
            Write-ShellLinkSuccess "Bitwarden CLI installed via npm"
            return
        }
    }

    # Direct download as last resort
    Write-ShellLinkStep "Downloading Bitwarden CLI directly..."
    $installDir = "$env:LOCALAPPDATA\ShellLink\bin"
    if (!(Test-Path $installDir)) { New-Item -ItemType Directory -Path $installDir -Force | Out-Null }

    $zipUrl = "https://vault.bitwarden.com/download/?app=cli&platform=windows"
    $zipPath = "$env:TEMP\bw-cli.zip"

    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
    Expand-Archive -Path $zipPath -DestinationPath $installDir -Force
    Remove-Item $zipPath -Force

    # Add to user PATH if not there
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -notlike "*$installDir*") {
        [Environment]::SetEnvironmentVariable("Path", "$userPath;$installDir", "User")
        $env:Path = "$env:Path;$installDir"
    }

    if (Get-Command bw -ErrorAction SilentlyContinue) {
        Write-ShellLinkSuccess "Bitwarden CLI installed successfully"
    } else {
        Exit-WithError "Failed to install Bitwarden CLI. Install manually: https://bitwarden.com/help/cli/"
    }
}

# ── Ensure OpenSSH ───────────────────────────────────────────
function Ensure-SSHTools {
    $ssh = Get-Command ssh -ErrorAction SilentlyContinue
    if ($ssh) {
        Write-ShellLinkInfo "OpenSSH client available"
        return
    }

    Write-ShellLinkStep "Installing OpenSSH client..."
    if (Test-IsAdmin) {
        Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
        Write-ShellLinkSuccess "OpenSSH client installed"
    } else {
        Write-ShellLinkWarn "Run as Administrator to install OpenSSH, or install it manually"
        Write-ShellLinkWarn "Settings > Apps > Optional Features > OpenSSH Client"
    }
}

# ── Ensure Git ───────────────────────────────────────────────
function Ensure-Git {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Write-ShellLinkInfo "Git already installed"
        return
    }

    Write-ShellLinkStep "Installing git..."
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        & winget install Git.Git --accept-package-agreements --accept-source-agreements
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    } else {
        Exit-WithError "Cannot install git automatically. Install from https://git-scm.com/"
    }
    Write-ShellLinkSuccess "Git installed"
}

# ── Main ─────────────────────────────────────────────────────
function Install-Dependencies {
    Show-ShellLinkHeader "Installing Dependencies"
    Ensure-Git
    Ensure-SSHTools
    Install-BitwardenCLI
    Write-ShellLinkSuccess "All dependencies ready"
}

# Run only when executed directly, not when dot-sourced
if ($MyInvocation.InvocationName -ne '.') {
    Install-Dependencies
}
