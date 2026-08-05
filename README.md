# Dotfiles

[![CI](https://github.com/Patruxs/dotfiles/actions/workflows/ci.yml/badge.svg)](https://github.com/Patruxs/dotfiles/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

An opinionated, cross-platform machine bootstrap system and dotfiles manager for Linux, macOS, and Windows. It uses **Ansible** for Linux and macOS orchestration and **Chezmoi** for configuration management.

> [!WARNING]
> The bootstrap scripts install software and change system settings. Review the repository before running them. Fork and customize it if you want to use it as your own dotfiles setup.

## 🚀 Quick Start

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

## ⚙️ How It Works

```text
Bootstrap script
       ↓
Choose OS and profile
       ↓
Install packages and apps
       ↓
Apply configs with Chezmoi
```

The bootstrap script detects your operating system and asks you to choose a `personal` or `work` profile. It then installs the selected packages and apps using Ansible on Linux and macOS, or PowerShell and Winget on Windows. Finally, Chezmoi applies your shell, Git, tmux, and editor configs.

## 🍴 Use It as Your Own

1. Fork this repository.
2. Replace `Patruxs/dotfiles` with your fork path in the bootstrap scripts, Chezmoi config, and README.
3. Replace the GPG recipient in `.chezmoi.toml.tmpl` with your own key.
4. Remove or replace the files in `private_dot_ssh/`. The private-key templates expect matching Bitwarden items and the tracked `.pub` files belong to this repository's owner.
5. Customize packages in `.chezmoidata/`, profiles in `ansible/vars/profiles/`, and configuration files in `.live/dotfiles/`.
6. Run `./test/test_harness.sh` before using the bootstrap script on your machine.

Never commit passwords, tokens, private SSH keys, or generated application state. See [CONTRIBUTING.md](CONTRIBUTING.md) for the development workflow.

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

## 🤝 Contributing

Issues and pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) and follow the [Code of Conduct](CODE_OF_CONDUCT.md).

For security problems, follow [SECURITY.md](SECURITY.md) instead of opening a public issue.

## 📄 License

Released under the [MIT License](LICENSE).
