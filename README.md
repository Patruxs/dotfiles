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

### 1. What is set up at the OS level?
- **Core CLI Tools**: `git`, `curl`, `wget`, `bash`, `neovim`, `tmux`, `btop`, `ripgrep`, `jq`, `bat`, `fzf` (plus `fd`, `eza`, `lazygit`, `gh` natively on Arch/macOS).
- **Development Tools**: `nodejs`, `npm`, `python3`, `python-pip`, `gcc`, `go`.
- **Desktop Base (Flatpak/Cask)**: VS Code, GitButler, Obsidian, GParted.
- **System Configs**: GNOME `dconf` settings, SSH host aliases, low-memory tuning (swap), Docker daemon setup.
- **Terminals**: Warp Terminal, Ghostty.
- **Docker**: Docker Engine (natively) and Docker Desktop.
*(Automatically detects and uses native package managers: APT, DNF, Pacman, Homebrew, plus Flatpak).*

### 2. What is stored in this repo?
- **Ansible Logic**: Modular playbooks (`setup.yml`, `ubuntu.yml`, `arch.yml`, etc.) and roles for OS detection and package installations.
- **Chezmoi Dotfiles**: Configuration templates (`*.tmpl`) that safely render secrets and symlink user settings (Bash, Git, Neovim, etc.) into `$HOME`.
- **Package Maps**: Structured YAML files (`package_sets/`) that cleanly map tools to their respective OS package managers.
- **Bootstrap Scripts**: Quick-start scripts (`bootstrap.sh`, `bootstrap.ps1`) to trigger the setup from zero.

### 3. What do the Personal vs. Work profiles set up?

The system is split into two primary profiles to keep work machines lean while fully tricking out personal machines.

| Feature / App Category | Personal Profile | Work Profile | Description / Apps Included |
| :--- | :---: | :---: | :--- |
| **Core CLI & Shell** | ✅ | ✅ | `git`, `curl`, `wget`, `bash`, `neovim`, `tmux`, `btop`, `ripgrep`, `jq`, `bat`, `fzf`, custom aliases (plus `fd`, `eza`, `lazygit`, `gh` on Arch/macOS) |
| **Dev Tools & SDKs** | ✅ | ✅ | `nodejs`, `npm`, `python3`, `python-pip`, `gcc`, `go`, global npm tools |
| **Desktop Base** | ✅ | ✅ | VS Code, GitButler, Obsidian, GParted |
| **Modern Terminals** | ✅ | ✅ | Warp Terminal, Ghostty |
| **Docker Engine & Desktop**| ✅ | ✅ | Native Docker daemon + Docker Desktop |
| **AI CLIs** | ✅ | ✅ | Local/cloud AI CLI tools and prompts |
| **GNOME Settings** | ✅ | ✅ | Custom `dconf` keybindings and UI tweaks |
| **Heavy IDEs** | ✅ | ❌ | JetBrains Toolbox, Kiro IDE |
| **Virtualization** | ✅ | ❌ | VirtualBox |
| **Desktop Apps (Media/Comm/Utils)** | ✅ | ❌ | Telegram, Zoom, Spotify, Postman, ONLYOFFICE, OBS Studio, Edge, Anki, Termius, Bazaar, `nvtop` |
</details>
