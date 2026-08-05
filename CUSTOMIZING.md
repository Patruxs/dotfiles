# Customize and Run Your Own Dotfiles

You can customize this project locally and run that exact checkout. You do not need to publish your changes first.

## 1. Fork or Clone

Fork the repository if you want to keep your version on GitHub, then clone it:

```sh
git clone https://github.com/YOUR_USERNAME/dotfiles.git
cd dotfiles
```

You can also clone the original repository directly if you only want a local version.

## 2. Choose Your Software

Edit the lists that control what gets installed:

- `.chezmoidata/packages.yaml` for system packages and applications
- `.chezmoidata/devtools.yaml` for development tools
- `.chezmoidata/ai-clis.yaml` for AI command-line tools
- `ansible/vars/profiles/personal.yml` for personal machines
- `ansible/vars/profiles/work.yml` for work machines

Remove anything you do not want before the first run.

## 3. Customize Your Configs

Edit the files in `.live/dotfiles/` for your shell, Git, tmux, Neovim, PowerShell, and terminal preferences.

Review these machine-specific areas carefully:

- `.live/ssh/config` contains example GitHub host aliases. Replace or remove them. Fresh installations ignore this file unless you opt in at the first-run prompt.
- `private_dot_ssh/` contains the original owner's public keys and Bitwarden templates. Remove the directory or replace it with your own setup. Never commit private keys.
- `dot_config/monitors.xml` contains a display layout that you may not want.
- `.chezmoidata/gnome_dconf.yaml` contains GNOME desktop preferences.
- `dot_config/opencode/opencode.jsonc.tmpl` references an optional local agent-instructions file.

Chezmoi asks for your Git name, Git email, and an optional GPG recipient on the first run. Leave the GPG recipient empty if you do not use encrypted Chezmoi files.

## 4. Run Your Local Checkout

The bootstrap script detects the checked-out repository and uses your local changes, including changes you have not committed.

**Linux or macOS**:

```sh
./bootstrap.sh --profile personal
```

Use `--profile work` for the work profile.

**Windows PowerShell**:

```powershell
.\bootstrap.ps1 -ProfileName personal
```

The bootstrap installs Chezmoi and other required setup tools. Chezmoi remembers this checkout as its source directory, so later commands continue to use your customized repository.

## 5. Preview and Update

After the first setup, preview configuration changes before applying them:

```sh
chezmoi diff
chezmoi apply --dry-run --verbose
chezmoi apply
```

Add another file with:

```sh
chezmoi add ~/.config/example/config
```

## 6. Test Your Changes

The test harness requires Chezmoi. Install it first if needed:

```sh
mkdir -p "$HOME/.local/bin"
curl -fsLS https://get.chezmoi.io | sh -s -- -b "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"
```

On Windows, install it with `winget install --id twpayne.chezmoi -e` and run the harness from Git Bash.

Then run the fast checks from the repository root:

```sh
./test/test_harness.sh
```

ShellCheck and Ansible checks run when those tools are available. The test harness always runs the bootstrap regression checks and a Chezmoi dry run.

## 7. Install From Your Published Fork

Commit and push your customization before installing it on another machine:

```sh
git add .
git commit -m "Customize dotfiles"
git push
```

Set `DOTFILES_REPO` so the downloaded bootstrap script clones your fork instead of the original repository.

**Linux**:

```sh
export DOTFILES_REPO="https://github.com/YOUR_USERNAME/dotfiles.git"
bash -c "$(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/dotfiles/main/bootstrap.sh)"
```

**macOS**:

```sh
export DOTFILES_REPO="https://github.com/YOUR_USERNAME/dotfiles.git"
bash -o pipefail -c 'curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/dotfiles/main/bootstrap.sh | bash'
```

**Windows PowerShell**:

```powershell
$env:DOTFILES_REPO = "https://github.com/YOUR_USERNAME/dotfiles.git"
irm https://raw.githubusercontent.com/YOUR_USERNAME/dotfiles/main/bootstrap.ps1 | iex
```

## 8. Update Project Links

If you publish the fork for other people, replace the original GitHub URLs in `README.md`, `SECURITY.md`, and `.github/ISSUE_TEMPLATE/config.yml` with your repository URLs. Keep the original MIT License copyright notice as required by the license.
