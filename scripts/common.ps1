# ╔══════════════════════════════════════════════════════════════╗
# ║              ShellLink — Common Utilities (PowerShell)       ║
# ╚══════════════════════════════════════════════════════════════╝
# Shared functions for all ShellLink PowerShell scripts.

$ErrorActionPreference = "Stop"

# ── Colors & Logging ─────────────────────────────────────────
function Write-ShellLinkInfo    { Write-Host "  i  " -ForegroundColor Cyan -NoNewline; Write-Host $args }
function Write-ShellLinkStep    { Write-Host "  >  " -ForegroundColor Blue -NoNewline; Write-Host $args }
function Write-ShellLinkSuccess { Write-Host "  +  " -ForegroundColor Green -NoNewline; Write-Host $args }
function Write-ShellLinkWarn    { Write-Host "  !  " -ForegroundColor Yellow -NoNewline; Write-Host $args }
function Write-ShellLinkError   { Write-Host "  X  " -ForegroundColor Red -NoNewline; Write-Host $args }

function Exit-WithError {
    param([string]$Message)
    Write-ShellLinkError $Message
    throw $Message
}

# ── Banner ───────────────────────────────────────────────────
function Show-ShellLinkBanner {
    Write-Host ""
    Write-Host "   _____ __         ____   __    _       __  " -ForegroundColor Cyan
    Write-Host "  / ___// /_  ___  / / /  / /   (_)___  / /__" -ForegroundColor Cyan
    Write-Host "  \__ \/ __ \/ _ \/ / /  / /   / / __ \/ //_/" -ForegroundColor Cyan
    Write-Host " ___/ / / / /  __/ / /  / /___/ / / / / ,<   " -ForegroundColor Cyan
    Write-Host "/____/_/ /_/\___/_/_/  /_____/_/_/ /_/_/|_|  " -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  SSH Bootstrap System - github.com/EpicSprout/ShellLink" -ForegroundColor DarkGray
    Write-Host "  ─────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
}

# ── Section Header ───────────────────────────────────────────
function Show-ShellLinkHeader {
    param([string]$Title)
    $pad = 42 - $Title.Length
    if ($pad -lt 0) { $pad = 0 }
    $padding = " " * $pad
    Write-Host ""
    Write-Host "  ┌─────────────────────────────────────────────┐" -ForegroundColor Magenta
    Write-Host "  │  $Title$padding│" -ForegroundColor Magenta
    Write-Host "  └─────────────────────────────────────────────┘" -ForegroundColor Magenta
    Write-Host ""
}

# ── Prompt helpers ───────────────────────────────────────────
function Read-ShellLinkValue {
    param(
        [string]$Prompt,
        [string]$Default = ""
    )
    if ($Default) {
        Write-Host "  ?  " -ForegroundColor Yellow -NoNewline
        $value = Read-Host "$Prompt [$Default]"
    } else {
        Write-Host "  ?  " -ForegroundColor Yellow -NoNewline
        $value = Read-Host $Prompt
    }
    if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
    return $value
}

function Read-ShellLinkSecret {
    param([string]$Prompt)
    Write-Host "  ?  " -ForegroundColor Yellow -NoNewline
    $secure = Read-Host $Prompt -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

# ── Admin check ──────────────────────────────────────────────
function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
