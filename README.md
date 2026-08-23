# Dotfiles

[![CI](https://github.com/Patruxs/dotfiles/actions/workflows/ci.yml/badge.svg)](https://github.com/Patruxs/dotfiles/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

<p align="center">
  <img width="400" height="250" alt="assets" src="https://github.com/user-attachments/assets/88f9d253-b01b-4b1d-8772-d4dbc80f5e95" />
</p>

An opinionated, cross-platform machine bootstrap system and dotfiles manager for Linux, macOS, and Windows. It uses **Ansible** for Linux and macOS orchestration and **Chezmoi** for configuration management.

> [!WARNING]
> The bootstrap scripts install software and change system settings. Review the repository before running them. Fork and customize it if you want to use it as your own dotfiles setup.

## 🚀 Quick start

Prerequisites: macOS needs [Homebrew](https://brew.sh) installed first; Windows needs `winget` (ships with App Installer on Windows 10/11). Linux needs only `curl` and `sudo`. Supported Linux platforms are Ubuntu, Fedora (including Fedora rebuilds such as Nobara), and Arch (including Manjaro and other `ID_LIKE=arch` derivatives).

**Linux**:

```sh
DOTFILES_REPO="https://github.com/Patruxs/dotfiles.git" \
  bash -o pipefail -c 'curl -fsSL https://raw.githubusercontent.com/Patruxs/dotfiles/main/bootstrap.sh | bash'
```

**macOS**:

```sh
DOTFILES_REPO="https://github.com/Patruxs/dotfiles.git" \
  bash -o pipefail -c 'curl -fsSL https://raw.githubusercontent.com/Patruxs/dotfiles/main/bootstrap.sh | bash'
```

**Windows (PowerShell)**:

```powershell
$env:DOTFILES_REPO = "https://github.com/Patruxs/dotfiles.git"
irm https://raw.githubusercontent.com/Patruxs/dotfiles/main/bootstrap.ps1 | iex
```

## ⚙️ How it works

```text
Bootstrap script
       ↓
Detect OS and desktop, choose profile
       ↓
Install packages and apps
       ↓
Apply configs with Chezmoi
```

The bootstrap script detects your operating system and, on Linux, your desktop environment, then asks you to choose a `personal` or `work` profile. It then installs the selected packages and apps using Ansible on Linux and macOS, or PowerShell and Winget on Windows. Finally, Chezmoi applies your configs: shell, Git, tmux, and editors (Neovim, Zed) on Linux and macOS; Git, PowerShell, Neovim, and Zed on Windows. Desktop settings follow the detected desktop: a GNOME session gets the `dconf` preferences and Shell extensions stored under `desktop_environment/gnome/`, a KDE Plasma session gets the settings stored under `desktop_environment/kde/`, and anything else gets neither (the report says so).

By default a step that fails (an upstream installer that is down, a package that does not exist on this release) is skipped and the run keeps going. Every skipped failure, with its error output, ends up in `~/.dotfiles_setup_report.md`, a Markdown report that is written on every run - even one that stops before Ansible starts - together with what was installed, what was skipped on purpose, and how to re-run. Pass `--strict` (or `-SetupMode strict` on Windows) to stop at the first failure instead. On Windows the configs are created as symlinks, which requires Developer Mode or an elevated shell (bootstrap checks this before applying). If OneDrive redirects your Documents folder, PowerShell loads its profile from `OneDrive\Documents` instead; link `Documents\PowerShell` there yourself.

## 📚 Documentation

| Document | What it covers |
| :--- | :--- |
| [Architecture](docs/architecture.md) | How a setup run works, the model behind it, and why it is built this way |
| [Adding a feature](docs/adding-a-feature.md) | Adding a tool, profile, or platform, as a checklist |
| [Reference](docs/reference.md) | Bootstrap flags, `DOTFILES_*` variables, and file formats |
| [Customizing](docs/customizing.md) | Forking this and making it your own |

## 🛠 Everyday usage

```sh
chezmoi add ~/.bashrc    # Manage a new file
chezmoi update -v        # Pull and apply latest changes
chezmoi diff             # See what will change
chezmoi doctor           # Troubleshoot issues
```

To run the bootstrap script manually with a specific profile:

```sh
./bootstrap.sh --profile personal
```

## 🧩 Desktop settings

Setup detects the desktop environment (`scripts/detect-desktop.sh`: the running
session first, then this user's session processes, then the installed session
files when nothing is running) and applies only that desktop's settings when a
profile includes `desktop_base`. `--desktop gnome|kde|none` or
`DOTFILES_DESKTOP` overrides the detection, for example over SSH on a machine
that has both desktops installed. The setup report records which desktop was
chosen and why.

```sh
./scripts/detect-desktop.sh --explain        # what setup will decide, and the evidence
```

### GNOME

Preferences live in `home/.chezmoidata/gnome_dconf.yaml` and are applied with
`dconf` inside a running GNOME session. Shell extension state is captured into
`desktop_environment/gnome/` and restored by the Ansible `gnome` role.

```sh
./scripts/gnome-extensions-sync.sh capture   # machine -> repo, then commit
./scripts/gnome-extensions-sync.sh apply     # repo -> machine
./scripts/gnome-extensions-sync.sh diff      # what drifted since the last capture
./scripts/gnome-extensions-sync.sh check     # exit 0 when already in sync
```

`capture` writes two files: `desktop_environment/gnome/extensions.dconf`, a `dconf` dump of every
per-extension setting, and `desktop_environment/gnome/extensions.yaml`, the list of which extensions
are enabled and whether they come from extensions.gnome.org or a distro package.
`apply` downloads the missing extensions.gnome.org ones, loads the settings, then
enables them - log out and back in afterwards for GNOME Shell to pick them up.

### KDE Plasma

Settings live in `desktop_environment/kde/settings/`, one INI fragment per KDE config file
(`kwinrc`, `kxkbrc`, `powerdevilrc`, ...), and are written key by key with
`kwriteconfig6` by the Ansible `kde` role. KDE rewrites its config files itself,
so they are never symlinked by chezmoi; only the stored keys are touched and
everything else in the live file is left alone.

```sh
./scripts/kde-settings-sync.sh capture       # machine -> repo, then commit
./scripts/kde-settings-sync.sh apply         # repo -> machine
./scripts/kde-settings-sync.sh diff          # what drifted since the last capture
./scripts/kde-settings-sync.sh check         # exit 0 when already in sync
```

`capture` copies a fixed list of KDE config files and drops the runtime state
KDE keeps in them (update stamps, window geometry, virtual desktop and screen
UUIDs, shortcuts still at their default). Panel layout and display layout are
machine state and are not captured.

## 🔑 Manual logins

```sh
gh auth login
docker login
ssh-keygen -t ed25519 -C "you@example.com"
```

## 🍴 Make it your own

Fork or clone the repository, replace the owner-specific values, and select the software and configs you want. Follow the [customization guide](docs/customizing.md) for the complete process.

> [!IMPORTANT]
> Never commit passwords, tokens, private SSH keys, or generated application state.

## 📁 Symlink mode

Chezmoi is set to `mode = "symlink"`. Tracked files are symlinked directly into `$HOME`. Any edits made by applications modify the tracked file here.

<details>
<summary><strong>Repository capabilities and profiles</strong></summary>

### Personal and work profiles

The system is split into two primary profiles to keep work machines lean while fully tricking out personal machines.

| Feature / App Category | OS | Personal Profile | Work Profile | Description / Apps Included |
| :--- | :--- | :---: | :---: | :--- |
| **Core CLI & Shell** | Linux, macOS, Windows | ✅ | ✅ | **Tools**: `git`, `curl`, `wget`, `unzip`, `gnupg`, `bash`, `neovim`, `ripgrep`, `jq`, `bat`, `fzf`, `zoxide`, `fd`, `eza`, `lazygit`, `gh`, `mole` (macOS). `tmux` and `btop` on Linux/macOS only. <br> **Configs**: Multi-shell integrations (`bash`, `zsh`, `powershell`), aliases, `.gitconfig` with GitHub CLI credential helper. The `shell` feature sets bash as the login shell on Linux and macOS. |
| **Dev Tools & SDKs** | Linux, macOS, Windows | ✅ | ✅ | **Languages**: `nodejs`, `python3`, `gcc`, `go`, `java`. (Plus POSIX UCRT on Windows). <br> **Package Mgrs**: `npm`, `python-pip`, `pnpm`, `uv`, `maven`, `gradle`. <br> **Testing**: `playwright`. |
| **Security / Passwords** | Linux, macOS, Windows | ✅ | ❌ | Bitwarden CLI (`bw`) installed via npm globally. |
| **Desktop Base** | Linux, macOS, Windows | ✅ | ✅ | **Editors**: VS Code, Zed, Obsidian. <br> **Utils**: GitButler, LocalSend, GParted (Linux), flatpak (Linux). |
| **Modern Terminals** | Linux, macOS, Windows | ✅ | ✅ | Warp Terminal. Ghostty on Linux and macOS (no Windows build). |
| **Docker Ecosystem** | Linux, macOS, Windows | ✅ | ✅ | Docker Desktop. A separate `docker_engine` feature exists for the native engine; no shipped profile selects it. |
| **AI CLIs** | Linux, macOS, Windows | ✅ | ✅ | `codex`, `agy`, `droid`, `opencode`, `herdr` (Plus `llmfit` installed natively on Personal only). |
| **System & Desktop Configs** | Linux, macOS, Windows | ✅ | ✅ | SSH host aliases. <br> **Linux-only**: GNOME `dconf` preferences and Shell extensions, or KDE Plasma settings, for whichever desktop is detected; `user-dirs.dirs` (XDG dirs), `auto-headphone-switch.service` (Systemd), swap/low-memory tuning. |
| **Heavy IDEs** | Linux, macOS, Windows | ✅ | ❌ | JetBrains Toolbox, Kiro IDE. |
| **Virtualization** | Linux, macOS, Windows | ✅ | ❌ | Oracle VirtualBox. |
| **Desktop Apps** | Linux, macOS, Windows | ✅ | ❌ | **Comm/Media**: Telegram, Zoom, Spotify, OBS Studio. <br> **Work/Utils**: Postman, ONLYOFFICE, Edge, Anki, Termius, Bazaar (Linux). <br> **System**: `nvtop` (Linux), TreeSize (Win), RevoUninstaller (Win). |

</details>

## 🤝 Contributing

Issues and pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) and follow the [Code of Conduct](CODE_OF_CONDUCT.md).

For security problems, follow [SECURITY.md](SECURITY.md) instead of opening a public issue.

## 📄 License

Released under the [MIT License](LICENSE).
