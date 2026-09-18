# Customize and Run Your Own Dotfiles

You can customize this project locally and run that exact checkout. You do not need to publish your changes first.

If you plan to change *how* setup works rather than *what* it installs, read [Architecture](architecture.md) first and then [Adding a feature](adding-a-feature.md).

## 1. Fork or Clone

Fork the repository if you want to keep your version on GitHub, then clone it:

```sh
git clone https://github.com/YOUR_USERNAME/dotfiles.git
cd dotfiles
```

You can also clone the original repository directly if you only want a local version.

## 2. Choose Your Software

Two different files answer two different questions. Start with the first one.

**Which capabilities does this machine want?** That is the profile:

- `ansible/vars/profiles/personal.yml`
- `ansible/vars/profiles/work.yml`

Delete any entry you do not want from the `features` list. Nothing is installed unless a profile asks for it, so removing a feature name here is the whole switch - there is no second place to also turn it off.

> [!NOTE]
> The `shell` feature sets bash as your login shell (`chsh`) on Linux and macOS. Remove it from your profile if you prefer zsh, fish, or another shell.

**Which packages actually provide them?** That is the package set for each operating system you use:

- `ansible/vars/package_sets/ubuntu.yml`
- `ansible/vars/package_sets/fedora.yml`
- `ansible/vars/package_sets/arch.yml`
- `ansible/vars/package_sets/macos.yml`

Each file maps feature names to package names for that OS. Edit only the ones you actually run - they are independent, and a run loads just one.

Three lists sit outside that split:

- `home/dot_config/mise/conf.d/<feature>.toml` - the user-level CLI tools a feature wants, shared across every platform and installed by [mise](https://mise.jdx.dev). One file per feature (`core_cli.toml`, `ai_clis.toml`, `npm_global_tools.toml`, ...), every entry `= "latest"`. Add a tool by adding a line (`mise registry` lists the short names; `"npm:<package>"`, `"github:<owner>/<repo>"` and the other backends work as well); remove one by deleting its line. The file is only applied when the profile selects both `mise` and that feature.
- `home/.chezmoidata/ai-clis.yaml` - AI command-line tools that only ship a vendor installer (`droid`), shared across platforms
- `home/.chezmoidata/packages.yaml` - the Windows package sets, keyed by feature like the Ansible package sets (`windows_package_sets.<feature>.winget`); `bootstrap.ps1` reads them through `chezmoi data` and installs the ones whose feature the profile selects

Remove anything you do not want before the first run.

## 3. Customize Your Configs

Edit the shell, Git, tmux, Neovim, PowerShell, and terminal files under `home/` (for example `home/dot_bashrc`, `home/dot_config/nvim/`). Chezmoi runs in symlink mode, so the deployed files in `$HOME` are symlinks back to these sources and edits take effect immediately either way.

Review these machine-specific areas carefully:

- `home/private_dot_ssh/private_config` contains example GitHub host aliases. Replace or remove them. Fresh installations ignore this file unless you opt in at the first-run prompt.
- `home/private_dot_ssh/` contains the original owner's public keys and Bitwarden templates. Remove the directory or replace it with your own setup. Never commit private keys. Fresh installations skip these keys unless you opt in at the first-run prompt (the keys are rendered from Bitwarden only when `bw` is on `PATH` and `BW_SESSION` holds an unlocked session; otherwise they stay ignored so the rest of the dotfiles still apply. On a new machine the first run installs `bw` through mise after `chezmoi apply`, so once setup has finished run `bw login`, export `BW_SESSION` from `bw unlock --raw`, and run `chezmoi apply` again).
- Desktop settings apply only for the desktop setup detects (`./scripts/detect-desktop.sh --explain` shows which); a GNOME machine never receives the KDE files and vice versa.
- `home/.chezmoidata/gnome_dconf.yaml` contains GNOME desktop preferences, including a keyboard input source with the Vietnamese ibus-bamboo IME. Replace that entry with your own layout (the IME engine itself is not installed by setup).
- `desktop_environment/gnome/extensions.dconf` and `desktop_environment/gnome/extensions.yaml` are the original owner's captured GNOME Shell extension set. Inside a GNOME session the Ansible `gnome` role installs and applies them automatically. Delete `desktop_environment/gnome/extensions.dconf` or re-capture with `./scripts/gnome-extensions-sync.sh capture` before your first run.
- `desktop_environment/kde/settings/` holds the original owner's KDE Plasma settings, one INI fragment per config file: the `us` keyboard layout with right Alt as the third-level key (`kxkbrc`), night light at 4700 K (`kwinrc`), the power button set to hibernate (`powerdevilrc`), and whatever `./scripts/kde-settings-sync.sh capture` has added since. Inside a KDE Plasma session the Ansible `kde` role applies them with `kwriteconfig6`. Edit the files by hand (they are plain KConfig INI) or delete them and re-capture from your own machine before your first run. Preferences that live in the panel - the clock format, the battery percentage - are part of the panel layout, which `./scripts/plasma-panels-sync.sh capture` stores in `desktop_environment/kde/panels.json` and the `kde` role rebuilds inside a Plasma session. The add-ons those settings enable (Krohnkite, the geometry change effect, Active Accent Frame, KDE Control Station) are installed by the `plasma_addons` feature through `./scripts/plasma-addons-install.sh`, and the JetBrainsMono Nerd Font the settings name comes from the `jetbrains_mono_nerd_font` feature (`./scripts/nerd-font-install.sh` on Fedora and Ubuntu).
- `home/dot_profile` sources `~/.profile.local` at the end. Put per-machine paths and aliases there; that file is never managed or committed.
- `home/.chezmoiscripts/` holds the run-once scripts chezmoi runs on the first apply (the Ghostty themes download, a one-time migration). Review them and delete any you do not want. In the default best-effort mode on Linux and macOS each script is applied on its own, so one failing script is recorded in the report and retried next time without blocking the other scripts or your dotfiles; `--strict` and the Windows bootstrap run a single `chezmoi apply`, which stops at the first failing script.
- `home/dot_config/ghostty/config` sets the `JetBrainsMono Nerd Font` font, which the `jetbrains_mono_nerd_font` feature installs (`./scripts/nerd-font-install.sh` on Fedora and Ubuntu, a package on Arch and macOS); change the `font-family` entries if you prefer another font. Its `theme` entry needs a theme file: `home/dot_config/ghostty/themes/` carries the ones this repo uses, and on Linux distributions whose Ghostty package omits the bundled theme catalogue (Fedora and Nobara) `run_once_after_install_ghostty_themes.sh.tmpl` downloads the rest into `~/.config/ghostty/themes` on the first `chezmoi apply`.
- `home/dot_config/opencode/opencode.jsonc.tmpl` references an optional local agent-instructions file.

Display layout (`~/.config/monitors.xml` on GNOME, `~/.config/kwinoutputconfig.json` and `~/.config/kscreen/` on KDE) is deliberately not managed - it is machine state, and `home/.chezmoiignore` guards it against an accidental `chezmoi add`. The same guard covers KDE's rc files (`kdeglobals`, `kwinrc`, ...): KDE rewrites them atomically, which would turn a chezmoi symlink into a plain file, so they are managed key by key from `kde/settings/` instead.

Chezmoi asks for your Git name, Git email, an optional GPG recipient, whether to apply the example SSH config, whether to provision the GitHub SSH keys from Bitwarden, and your dotfiles profile (`personal` or `work`) on the first run. Leave the GPG recipient empty if you do not use encrypted Chezmoi files. Answers are stored in `~/.config/chezmoi/chezmoi.toml`; to change one, edit that file (or delete it and re-run `chezmoi init`).

Chezmoi generates `~/.gitconfig.local` (your Git identity) and overwrites it on apply. Put hand-maintained per-machine Git settings in `~/.gitconfig.machine` instead; it is included by the shared gitconfig and never touched by Chezmoi.

For automation outside GitHub Actions, set `DOTFILES_CI=1` so `chezmoi init` uses non-interactive defaults instead of prompting.

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

ShellCheck, yamllint, ansible-lint and Ansible checks run when those tools are available. The test harness always runs the bootstrap regression checks and a Chezmoi dry run.

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
bash -o pipefail -c 'curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/dotfiles/main/bootstrap.sh | bash'
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
