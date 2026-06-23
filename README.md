# dotfiles

Public chezmoi repo for shell config, Git config, selected app config, package bootstrapping, Lazygit and GitButler setup, VS Code settings/extensions, GNOME settings, Docker daemon settings, and a safe SSH config.

This repo is configured for chezmoi `symlink` mode. On `chezmoi apply`, eligible managed files are linked back to the source directory instead of being copied.

Not managed: secrets, tokens, auth/session state, SSH keys, Docker auth, GitHub CLI auth, browser profiles, VS Code state, monitor layouts, binary dconf, caches.

## Setup

Linux:

```sh
bash -o pipefail -c 'if command -v curl >/dev/null 2>&1; then curl -fsSL https://raw.githubusercontent.com/Patruxs/dotfiles/main/bootstrap.sh | bash; elif command -v wget >/dev/null 2>&1; then wget -qO- https://raw.githubusercontent.com/Patruxs/dotfiles/main/bootstrap.sh | bash; elif command -v apt-get >/dev/null 2>&1; then sudo apt-get update && sudo apt-get install -y curl && curl -fsSL https://raw.githubusercontent.com/Patruxs/dotfiles/main/bootstrap.sh | bash; else echo "Install curl or wget first."; exit 1; fi'
```

macOS:

```sh
bash -o pipefail -c 'curl -fsSL https://raw.githubusercontent.com/Patruxs/dotfiles/main/bootstrap.sh | bash'
```

Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/Patruxs/dotfiles/main/bootstrap.ps1 | iex
```

Fast mode:

```sh
DOTFILES_AUTO_INSTALL=1 bash bootstrap.sh
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

Run setup manually:

```sh
ansible-playbook ansible/playbooks/setup.yml
```

This runs the main orchestration playbook to install packages and configure the system.

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
- Files that used to need templates for live syncing now point at tracked backing files in [.live/](/home/pat/.local/share/chezmoi/.live): shell dotfiles, `~/.ssh/config`, and Docker.
- `~/.gitconfig` stays symlinked to the tracked shared config and includes a generated `~/.gitconfig.local` for per-machine `user.name` and `user.email`.

Useful checks:

```sh
chezmoi status
chezmoi managed --include files
find "$HOME" -maxdepth 3 -type l
```

<details>
<summary>What This repo does , setup , store </summary>

What this repo does:
- Acts as a cross-platform machine bootstrap system and dotfiles manager for Linux, macOS, and Windows.
- Uses Ansible as the primary orchestration layer for OS detection, profile selection (personal/work), and role-based setups.
- Uses Chezmoi for dotfile templating, secret handling, and managing configurations in `symlink` mode.

Setup:
- Automatically detects OS and installs Chezmoi and Ansible if missing.
- Installs system packages and desktop apps using native package managers (dnf, apt, pacman, Homebrew, Winget) and Flatpak.
- Installs Lazygit and GitButler during setup without managing either app's config files.
- Applies system configurations like GNOME `dconf` settings, Docker daemon, SSH host aliases, and user `systemd` services.
- Renders templates and symlinks user dotfiles (Zsh, Git, Ghostty) into `$HOME`.

Store:
- Ansible logic including playbooks, roles (base, packages, git_tools, flatpak, gnome, shell, docker), and profile variables.
- Package definitions in `.chezmoidata/packages.yaml` grouped by common, personal, and work profiles.
- Dotfile templates (`*.tmpl`), ignore rules, and configuration sources.
- Bootstrap scripts (`bootstrap.sh`, `bootstrap.ps1`) to trigger the setup flow.
</details>
