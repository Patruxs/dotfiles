# Dotfiles

Cross-platform machine bootstrap system and dotfiles manager for Linux, macOS, and Windows. Uses **Ansible** for orchestration and **Chezmoi** for symlinking.

## 🚀 Setup

**Linux**:
```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Patruxs/dotfiles/main/bootstrap.sh)"
```

**macOS**:
```sh
bash -o pipefail -c 'curl -fsSL https://raw.githubusercontent.com/Patruxs/dotfiles/main/bootstrap.sh | bash'
```

**Windows (PowerShell)**:
```powershell
irm https://raw.githubusercontent.com/Patruxs/dotfiles/main/bootstrap.ps1 | iex
```

## 🛠 Usage

```sh
chezmoi add ~/.bashrc    # Manage a new file
chezmoi update -v        # Pull and apply latest changes
chezmoi diff             # See what will change
chezmoi doctor           # Troubleshoot issues
```

*Manual Setup*: `./bootstrap.sh --profile personal`

## 🔑 Manual Logins
```sh
gh auth login
docker login
ssh-keygen -t ed25519 -C "you@example.com"
```

## 📁 Symlink Mode
Chezmoi is set to `mode = "symlink"`. Tracked files are symlinked directly into `$HOME`. Any edits made by applications modify the tracked file here.


<details>
<summary>Repository Capabilities & Profiles</summary>

### What do the Personal vs. Work profiles set up?

The system is split into two primary profiles to keep work machines lean while fully tricking out personal machines.

| Feature / App Category | OS | Personal Profile | Work Profile | Description / Apps Included |
| :--- | :--- | :---: | :---: | :--- |
| **Core CLI & Shell** | Linux, macOS, Windows | ✅ | ✅ | **Tools**: `git`, `curl`, `wget`, `unzip`, `gnupg`, `bash`, `neovim`, `tmux`, `btop`, `ripgrep`, `jq`, `bat`, `fzf`, `zoxide`, `fd`, `eza`, `lazygit`, `gh`, `mole` (macOS). <br> **Configs**: Multi-shell integrations (`bash`, `zsh`, `powershell`), aliases, `.gitconfig` with GitHub CLI credential helper. |
| **Dev Tools & SDKs** | Linux, macOS, Windows | ✅ | ✅ | **Languages**: `nodejs`, `python3`, `gcc`, `go`, `java`. (Plus POSIX UCRT on Windows). <br> **Package Mgrs**: `npm`, `python-pip`, `pnpm`, `uv`, `maven`, `gradle`. <br> **Testing**: `playwright`. |
| **Security / Passwords** | Linux, macOS, Windows | ✅ | ❌ | Bitwarden CLI (`bw`) installed via npm globally. |
| **Desktop Base** | Linux, macOS, Windows | ✅ | ✅ | **Editors**: VS Code, Obsidian. <br> **Utils**: GitButler, LocalSend, GParted (Linux), flatpak (Linux). |
| **Modern Terminals** | Linux, macOS, Windows | ✅ | ✅ | Warp Terminal, Ghostty. |
| **Docker Ecosystem**| Linux, macOS, Windows | ✅ | ✅ | Native Docker Engine + Docker Desktop. |
| **AI CLIs** | Linux, macOS, Windows | ✅ | ✅ | `codex`, `agy`, `droid`, `opencode`, `herdr` (Plus `llmfit` installed natively on Personal only). |
| **System & Desktop Configs**| Linux, macOS, Windows | ✅ | ✅ | SSH host aliases. <br> **Linux-only**: GNOME `dconf` keybindings & UI tweaks, `monitors.xml` (display layout), `user-dirs.dirs` (XDG dirs), `auto-headphone-switch.service` (Systemd), swap/low-memory tuning. |
| **Heavy IDEs** | Linux, macOS, Windows | ✅ | ❌ | JetBrains Toolbox, Kiro IDE. |
| **Virtualization** | Linux, macOS, Windows | ✅ | ❌ | Oracle VirtualBox. |
| **Desktop Apps** | Linux, macOS, Windows | ✅ | ❌ | **Comm/Media**: Telegram, Zoom, Spotify, OBS Studio. <br> **Work/Utils**: Postman, ONLYOFFICE, Edge, Anki, Termius, Bazaar (Linux). <br> **System**: `nvtop` (Linux), TreeSize (Win), RevoUninstaller (Win). |

</details>
