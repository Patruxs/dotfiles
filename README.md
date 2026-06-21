# dotfiles

Public chezmoi repo for shell config, Git config, selected app config, package bootstrapping, mise runtimes, VS Code settings/extensions, GNOME settings, Docker daemon settings, and a safe SSH config.

This repo is configured for chezmoi `symlink` mode. On `chezmoi apply`, eligible managed files are linked back to the source directory instead of being copied.

Not managed: secrets, tokens, auth/session state, SSH keys, Docker auth, GitHub CLI auth, browser profiles, VS Code state, monitor layouts, binary dconf, caches.

## Setup

Linux:

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/Patruxs/dotfiles/main/bootstrap.sh)"
```

macOS:

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/Patruxs/dotfiles/main/bootstrap.sh)"
```

Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/Patruxs/dotfiles/main/bootstrap.ps1 | iex
```

Fast mode:

```sh
DOTFILES_AUTO_INSTALL=1 sh bootstrap.sh
```

## Use

Add a dotfile:

```sh
chezmoi add ~/.zshrc
git -C ~/.local/share/chezmoi status
```

Update another machine:

```sh
chezmoi update -v
```

Check rendered config:

```sh
chezmoi cat-config | rg '^mode = "symlink"$'
```

Install packages manually:

```sh
bash ~/.chezmoiscripts/10-install-system-packages.sh
bash ~/.chezmoiscripts/20-install-devtools.sh
bash ~/.chezmoiscripts/30-install-flatpaks.sh
```

These rendered helper scripts are created by `chezmoi apply`.

## Manual login

```sh
gh auth login
docker login
codex
claude
agy
droid
opencode   # then /connect
```

## SSH

```sh
ssh-keygen -t ed25519 -C "you@example.com"
```

## Troubleshooting

```sh
chezmoi doctor
chezmoi diff
chezmoi apply --dry-run --verbose
```

## Symlink Mode

Chezmoi is configured with `mode = "symlink"` in [.chezmoi.toml.tmpl](/home/pat/.local/share/chezmoi/.chezmoi.toml.tmpl:1).

What this means:
- Regular non-templated managed files are symlinked into `$HOME` on `chezmoi apply`.
- Templates, `private_` files, encrypted files, executable files, and directories are still managed normally by chezmoi and are not symlinked.
- If a program edits a symlinked config file, it is editing the tracked source file in this repo.
- Files that used to need templates for live syncing now point at tracked backing files in [.live/](/home/pat/.local/share/chezmoi/.live): shell dotfiles, `~/.ssh/config`, `mise`, and Docker.
- `~/.gitconfig` stays symlinked to the tracked shared config and includes a generated `~/.gitconfig.local` for per-machine `user.name` and `user.email`.

Useful checks:

```sh
chezmoi status
chezmoi managed --include files
find "$HOME" -maxdepth 3 -type l
```

<details>
<summary>What This Repo Stores And Sets Up</summary>

Store :
- Shell config for `~/.profile`, Bash, and Zsh, including PATH setup and `mise` activation.
- Git config for user identity, default branch, and GitHub CLI credential helper.
- `chezmoi` config for prompts, repo metadata, and `gpg` encryption settings.
- Runtime and tool version config for `mise` with Node.js, Java, Go, Python, `pnpm`, `uv`, Maven, and Gradle.
- Package lists for Linux package managers, Homebrew, Winget, and Linux Flatpak apps.
- AI CLI install metadata for `codex`, `claude`, `agy`, `droid`, and `opencode`.
- App and system config for Ghostty, the Nord Ghostty theme, Docker daemon, Fcitx5, XDG user dirs, OpenCode, and a user `systemd` service.
- Safe SSH host aliases in `~/.ssh/config` for personal and work GitHub identities.
- Shared `chezmoi` data, helper templates, and ignore rules used to render files and control what is managed.

Setup:
- Installs `chezmoi` if needed, initializes this dotfiles repo, shows a diff, and applies managed files.
- Prompts for Git name and email the first time `chezmoi` renders templates, then writes them to `~/.gitconfig.local`.
- Prepares local directories such as `~/.local/bin`, `~/.local/share/pnpm`, and `~/.config/mise`.
- Installs curated system packages with `dnf`, `apt`, `pacman`, or Homebrew depending on the OS.
- Installs and updates development runtimes and tools through `mise`.
- Installs curated Flatpak desktop apps on Linux.
- Installs optional AI CLIs on Unix-like systems.
- Loads curated GNOME `dconf` settings on GNOME-based Linux systems.
- Reloads user `systemd`, enables the `auto-headphone-switch` service, and reminds you to switch to `zsh` manually.
- On Windows, imports curated `winget` packages and prints AI CLI install commands.
- Optionally switches the local dotfiles repo remote from HTTPS to SSH after bootstrap.
</details>
