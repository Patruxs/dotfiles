# Customizing These Dotfiles

This guide explains how to turn this repository into your own machine setup.

## 1. Fork and Clone

Fork the repository on GitHub, then clone your fork:

```sh
git clone https://github.com/YOUR_USERNAME/dotfiles.git
cd dotfiles
```

## 2. Replace the Repository Owner

Replace `Patruxs/dotfiles` with `YOUR_USERNAME/dotfiles` in:

- `bootstrap.sh`
- `bootstrap.ps1`
- `.chezmoi.toml.tmpl`
- `README.md`

Also replace `Patruxs` in GitHub links and repository metadata.

## 3. Configure Your Identity

Chezmoi asks for your Git name and email during setup. Replace the GPG recipient in `.chezmoi.toml.tmpl` if you plan to encrypt files with Chezmoi.

The files in `private_dot_ssh/` belong to the original owner. Remove them or replace them with your own SSH setup before running the bootstrap script. Never commit a private SSH key. The existing private-key templates expect secrets stored in matching Bitwarden items.

## 4. Choose Your Software

Edit these files to select what your machines install:

- `.chezmoidata/packages.yaml` for system packages and applications
- `.chezmoidata/devtools.yaml` for development tools
- `.chezmoidata/ai-clis.yaml` for AI command-line tools
- `ansible/vars/profiles/personal.yml` for personal machines
- `ansible/vars/profiles/work.yml` for work machines

Remove anything you do not use before your first installation.

## 5. Customize Your Configs

Edit the tracked configs in `.live/dotfiles/`, including shell, Git, tmux, Neovim, PowerShell, and terminal settings.

To add another file after setup:

```sh
chezmoi add ~/.config/example/config
```

Preview changes before applying them:

```sh
chezmoi diff
chezmoi apply --dry-run --verbose
```

## 6. Test Your Fork

Run the fast checks from the repository root:

```sh
./test/test_harness.sh
```

Review the bootstrap script before testing it on a real machine because it installs software and changes system settings.

## 7. Install From Your Fork

Update the username in the command for your platform:

**Linux**:

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/dotfiles/main/bootstrap.sh)"
```

**macOS**:

```sh
bash -o pipefail -c 'curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/dotfiles/main/bootstrap.sh | bash'
```

**Windows**:

```powershell
irm https://raw.githubusercontent.com/YOUR_USERNAME/dotfiles/main/bootstrap.ps1 | iex
```

After installation, use `chezmoi diff` before applying updates from your fork.
