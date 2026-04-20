<div align="center">

```
   _____ __         ____   __    _       __  
  / ___// /_  ___  / / /  / /   (_)___  / /__
  \__ \/ __ \/ _ \/ / /  / /   / / __ \/ //_/
 ___/ / / / /  __/ / /  / /___/ / / / / ,<   
/____/_/ /_/\___/_/_/  /_____/_/_/ /_/_/|_|  
```

**One command. Every machine. SSH ready.**

[![Platform](https://img.shields.io/badge/platform-linux%20%7C%20macOS%20%7C%20windows-blue)]()
[![License](https://img.shields.io/badge/license-MIT-green)]()
[![Shell](https://img.shields.io/badge/bash-%23121011.svg?logo=gnu-bash&logoColor=white)]()
[![PowerShell](https://img.shields.io/badge/PowerShell-%235391FE.svg?logo=powershell&logoColor=white)]()

</div>

---

## What is ShellLink?

ShellLink is a cross-platform SSH bootstrap system that takes you from a **fresh machine** to `ssh myserver` with a **single command**.

It uses **Bitwarden** as your secure key vault — no more copying SSH keys around on USB drives or pasting them into Slack.

### What it does:

1. **Installs dependencies** — Bitwarden CLI, OpenSSH, git (+ jq on Linux/macOS)
2. **Authenticates with Bitwarden** — API key login + vault unlock
3. **Retrieves your SSH key** — from a Secure Note, custom field, or attachment
4. **Configures ssh-agent** — starts the agent and loads your key
5. **Syncs SSH config** — clones this repo and generates your SSH config from `.env`

---

## Quick Start

### Linux / macOS

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/EpicSprout/ShellLink/main/bootstrap.sh)"
```

### Windows (PowerShell)

```powershell
iwr https://raw.githubusercontent.com/EpicSprout/ShellLink/main/bootstrap.ps1 | iex
```

That's it. One command.

---

## Prerequisites

### 1. Store your SSH key in Bitwarden

ShellLink looks for a Bitwarden vault item (default name: `ssh-key`). You can store the private key in any of these formats:

| Method | How |
|--------|-----|
| **Secure Note** (recommended) | Create a Secure Note named `ssh-key`, paste the full private key into the **Notes** field |
| **Custom Field** | On any item, add a custom field named `private-key` with the key as the value |
| **Attachment** | Attach a file named `id_ed25519` (or `id_rsa`) to any item named `ssh-key` |

### 2. Create a Bitwarden API Key

1. Go to [vault.bitwarden.com](https://vault.bitwarden.com) → **Settings** → **Security** → **Keys**
2. Under **API Key**, click **View API Key**
3. Note your `client_id` and `client_secret`

You can either:
- **Set environment variables** before running (recommended for automation):
  ```bash
  export BW_CLIENTID="user.xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  export BW_CLIENTSECRET="xxxxxxxxxxxxxxxxxxxxxxxxxxxx"
  ```
- **Let ShellLink prompt you** during setup

---

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `BW_CLIENTID` | Bitwarden API client ID | *(prompted)* |
| `BW_CLIENTSECRET` | Bitwarden API client secret | *(prompted)* |
| `SHELLLINK_KEY` | Bitwarden item name for SSH key | `ssh-key` |
| `SHELLLINK_MODE` | `disk` (write key to file) or `agent` (memory only) | `disk` |
| `SHELLLINK_REPO` | Custom repo URL for SSH config | `EpicSprout/ShellLink` |

### Command Line Options

#### Bash
```bash
./bootstrap.sh [OPTIONS]

  -k, --key NAME      Bitwarden item name for SSH key (default: ssh-key)
  -a, --agent-only    Load key into ssh-agent only (no disk write)
  -d, --disk          Write key to disk and load into agent (default)
  --skip-config       Skip SSH config sync
  -h, --help          Show help
```

#### PowerShell
```powershell
.\bootstrap.ps1 [OPTIONS]

  -Key NAME           Bitwarden item name for SSH key (default: ssh-key)
  -AgentOnly          Load key into ssh-agent only (no disk write)
  -SkipConfig         Skip SSH config sync
  -Help               Show help
```

---

## SSH Config

ShellLink generates your SSH config from a **template** and a **`.env` file**. This keeps secrets (hostnames, usernames) out of version control.

### How it works

1. [`ssh-config/config.template`](ssh-config/config.template) defines global SSH defaults (e.g., `AddKeysToAgent`, `ServerAliveInterval`)
2. `ssh-config/.env` defines your host entries using `HOST_<alias>_<PROPERTY>=value` variables
3. At bootstrap time, ShellLink merges the template + `.env` into a generated `ssh-config/config` and installs it to `~/.ssh/config`

### Setting up your hosts

1. Copy the example file:
   ```bash
   cp ssh-config/.env.example ssh-config/.env
   ```
2. Edit `ssh-config/.env` with your real values:
   ```bash
   HOST_myserver_LABEL=My Server
   HOST_myserver_HOSTNAME=192.168.1.100
   HOST_myserver_USER=youruser
   HOST_myserver_PORT=22
   HOST_myserver_IDENTITY_FILE=~/.ssh/id_ed25519
   ```
3. To add more hosts, add another `HOST_<alias>_` block:
   ```bash
   HOST_github_LABEL=GitHub
   HOST_github_HOSTNAME=github.com
   HOST_github_USER=git
   HOST_github_IDENTITY_FILE=~/.ssh/id_ed25519
   ```

### `.env` properties

| Property | Required | Default | Description |
|----------|----------|---------|-------------|
| `HOSTNAME` | Yes | — | Server address |
| `USER` | No | — | SSH username |
| `PORT` | No | `22` | SSH port |
| `IDENTITY_FILE` | No | `~/.ssh/id_ed25519` | Path to private key |
| `LABEL` | No | alias name | Comment label in generated config |

> **Note:** `ssh-config/.env` is gitignored — it stays local to each machine. Only `.env.example` and `config.template` are tracked in the repo.

---

## How It Works

```
┌─────────────────────────────────────────────────────────┐
│                     ShellLink Bootstrap                 │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  1. curl/iwr → downloads bootstrap script               │
│  2. Clones ShellLink repo to temp directory             │
│  3. Installs: bw, git, jq, openssh                      │
│  4. Authenticates with Bitwarden API key                │
│  5. Unlocks vault with master password                  │
│  6. Retrieves SSH key from vault item                   │
│  7. Starts ssh-agent                                    │
│  8. Loads key into agent (+ writes to ~/.ssh/)          │
│  9. Clones config repo → ~/.ssh-config/                 │
│ 10. Generates config from template + .env               │
│ 11. Installs config → ~/.ssh/config                     │
│                                                         │
  ... Result: ssh myserver ✔
└─────────────────────────────────────────────────────────┘
```

---

## Project Structure

```
ShellLink/
├── bootstrap.sh          # Entry point (Linux/macOS)
├── bootstrap.ps1         # Entry point (Windows)
├── scripts/
│   ├── common.sh         # Shared utilities (bash)
│   ├── common.ps1        # Shared utilities (PowerShell)
│   ├── install.sh        # Dependency installer (bash)
│   ├── install.ps1       # Dependency installer (PowerShell)
│   ├── bw-auth.sh        # Bitwarden auth (bash)
│   ├── bw-auth.ps1       # Bitwarden auth (PowerShell)
│   ├── ssh-setup.sh      # SSH agent & key setup (bash)
│   └── ssh-setup.ps1     # SSH agent & key setup (PowerShell)
├── ssh-config/
│   ├── config.template   # Global SSH defaults (tracked)
│   └── .env.example      # Example host definitions (tracked)
├── .gitignore
└── README.md
```

---

## Security

ShellLink is designed with security in mind:

- **No secrets in code** — all credentials come from environment variables or interactive prompts
- **No logging of sensitive data** — passwords and keys are never echoed or written to logs
- **Secure memory handling** — passwords are cleared from variables after use
- **Proper file permissions** — keys are `chmod 600`, `.ssh/` is `chmod 700`
- **Agent-only mode** — optionally keep keys only in memory, never on disk
- **Secure temp file cleanup** — temp files are shredded (Linux) or overwritten with random data (Windows)
- **Bitwarden API keys** — uses API key auth (not password-based login), supports 2FA

---

## Multiple Keys

To use multiple SSH keys, create separate items in Bitwarden and run ShellLink for each:

```bash
# Load your personal key
SHELLLINK_KEY="ssh-key-personal" ./bootstrap.sh

# Load your work key
SHELLLINK_KEY="ssh-key-work" ./bootstrap.sh --skip-config
```

---

## Troubleshooting

### "Item not found in Bitwarden vault"
- Make sure the item name matches exactly (default: `ssh-key`)
- Run `bw sync` to refresh the vault cache
- Check that the key is stored in the notes field, a custom field named `private-key`, or as an attachment

### "Failed to unlock vault"
- Double-check your master password
- Ensure `BW_CLIENTID` and `BW_CLIENTSECRET` are correct
- Try `bw logout` and re-run

### "ssh-agent not running" (Windows)
- Open PowerShell as Administrator
- Run: `Set-Service -Name ssh-agent -StartupType Automatic; Start-Service ssh-agent`

### "Permission denied" on SSH key
- Linux/macOS: `chmod 600 ~/.ssh/id_ed25519`
- Windows: Right-click → Properties → Security → Remove all users except yourself

### SSH config not working
- Ensure `ssh-config/.env` exists and has valid `HOST_` entries
- Check `~/.ssh/config` exists and was generated correctly
- Verify permissions: `ls -la ~/.ssh/config` should show `-rw-------`
- On Linux/macOS, `~/.ssh/config` is symlinked to the generated config; on Windows it's copied

---

## Updating

To update ShellLink on a machine where it's already set up:

```bash
cd ~/.ssh-config && git pull
```

Or just re-run the bootstrap command — it handles updates automatically.

---

## License

MIT — use it, fork it, make it yours.

---

<div align="center">

**Built with 💙 by [EpicSprout](https://github.com/EpicSprout)**

*From zero to SSH in one command.*

</div>
