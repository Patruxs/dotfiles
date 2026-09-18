# Reference

Flags, environment variables, and file formats. See [Architecture](architecture.md) for what these things do to a run.

## bootstrap.sh (Linux and macOS)

```sh
./bootstrap.sh [--profile personal|work] [--platform ubuntu|fedora|arch|macos] [--desktop gnome|kde|none] [--best-effort|--strict] [--no-system-upgrade]
```

| Flag | Default | Description |
| :--- | :--- | :--- |
| `--profile <name>` | `DOTFILES_PROFILE`, or prompt | Which profile to install. Accepted values are `personal` and `work`, validated in `bootstrap.sh`, `bootstrap.ps1`, and `home/.chezmoi.toml.tmpl` (new profiles must be added to all three). |
| `--platform <name>` | detected from the OS | Override platform detection. **Rejected unless `DOTFILES_CI=1`** - a real machine must not be able to lie about its OS. |
| `--desktop <name>` | `DOTFILES_DESKTOP`, or detected | Which desktop's settings to apply on Linux: `gnome`, `kde`, or `none` (apply neither). Without it `scripts/detect-desktop.sh` decides from the running session, this user's session processes, or the installed session files. Allowed on real machines, unlike `--platform`, because a machine with two desktops installed and no session running (setup over SSH) genuinely needs to be told. |
| `--best-effort` | this is the default | Skip a failing step and keep going, recording every skipped failure in the final report. Applies to the bootstrap prerequisite steps as well as package installs, feature roles, each `chezmoi` script, and services. |
| `--strict` | | Stop at the first failure. Use this while developing. The report still records where the run stopped. |
| `--no-system-upgrade` | | Skip the system package refresh (`dnf upgrade`, `apt-get upgrade`, `pacman -Syu`, or `nobara-sync`) that otherwise runs before anything is installed. Use it to install a tool without pulling in a full system upgrade; the report records the step as skipped. On Ubuntu the apt package index is still refreshed before packages are installed. |

The script detects the OS, maps it to a platform, installs chezmoi, git, Ansible, and the required collections, detects the desktop environment (see [Desktop settings](#desktop-settings)), then runs exactly one playbook: `ansible/playbooks/<platform>.yml`. On macOS, Homebrew must already be installed - without it the first step that needs a package (usually installing Ansible) aborts the run, and the report says so.

Prerequisite steps that the rest of the run cannot work without stop the run even in best-effort mode: installing chezmoi (after the installer script, a direct GitHub release download, and the distro package manager have all been tried), cloning the repository, installing Ansible, and a required Ansible collection that is missing. Everything else (system package refresh, curl, git, chezmoi self-upgrade, `chezmoi init` from a checkout, refreshing the repository, refreshing collections from Galaxy) is skipped on failure and reported.

On Ubuntu, a `curl` that resolves to the Snap build is replaced with the native package before anything is downloaded; Snap confinement breaks upstream installer scripts that write to `/tmp`.

Exit status: `0` when the playbook finished, even with skipped failures (read the report); non-zero when a critical step or strict mode stopped the run.

Distro mapping (from `/etc/os-release`): `ubuntu` to `ubuntu`, `fedora` to `fedora`, `arch` and `manjaro` to `arch`, Darwin to `macos`. Rebuilds of a supported distro are followed through `ID_LIKE`: a Fedora rebuild (Nobara, Ultramarine - `ID_LIKE` contains `fedora` and `PLATFORM_ID` is `platform:fNN`) takes the `fedora` path, and an Arch derivative (`ID_LIKE` contains `arch`) takes the `arch` path. Enterprise Linux (RHEL, AlmaLinux, Rocky, CentOS) also lists `fedora` in `ID_LIKE` but builds on `platform:elN`, so it is rejected rather than sent down a path whose repos and package names it does not share. Ubuntu derivatives are not followed because the Ubuntu path depends on Ubuntu release codenames. Image-based systems (`/run/ostree-booted` exists: Fedora Silverblue/Kinoite, Bazzite, Bluefin, other ostree/bootc images) are rejected even when their os-release identity would map onto the Fedora path, because their read-only `/usr` cannot take dnf installs. Anything else fails early with an explicit message naming the real `ID`. The setup report records the real distro next to the platform when they differ.

On Nobara, the system package refresh runs `nobara-sync cli` (Nobara's own updater, which wraps the dnf transaction with its fixups) instead of a raw `dnf upgrade`; everything after that is the plain Fedora path. Fedora-only third-party repos are added only when needed: the Ghostty Copr and RPM Fusion (VirtualBox) are skipped when an enabled repo already provides the package, which is the case for Ghostty on Nobara (Terra). The `virtualbox` feature follows the Fedora path on Nobara too (RPM Fusion Free is added when no enabled repo provides VirtualBox; `rpm -E %fedora` resolves the matching release).

## bootstrap.ps1 (Windows)

```powershell
.\bootstrap.ps1 [-ProfileName personal|work] [-SetupMode best_effort|strict]
```

Windows uses winget and PowerShell rather than Ansible. It shares the profile and setup-mode vocabulary but not the playbook structure. `winget` must be available (it ships with App Installer); the script fails early without it. The chosen profile is cached in `~/.dotfiles_profile` and offered as the default on later runs.

The package list is the union of `windows_package_sets.<feature>.winget` in `home/.chezmoidata/packages.yaml` over the features the profile selects, so dropping a feature from a profile drops its Windows packages too. Packages are installed with one `winget import --ignore-versions` (the import manifest is built at run time), which installs whatever is missing at its latest version and converts already-installed packages to an upgrade (winget only leaves them alone when `--no-upgrade` is passed), so every re-run keeps the managed packages current. When the profile selects `mise`, bootstrap then installs `jdx.mise` with winget, adds `%LOCALAPPDATA%\mise\shims` to the user `PATH`, and runs `mise install` and `mise upgrade` for the tool lists chezmoi applied; in best-effort mode a failure there is recorded and the run continues.

## Environment variables

### Common

| Variable | Default | Description |
| :--- | :--- | :--- |
| `DOTFILES_REPO` | none | Repository to clone. Required when running a downloaded bootstrap script; ignored when running from a checkout. |
| `DOTFILES_PROFILE` | none | Profile to use, equivalent to `--profile`. |
| `DOTFILES_SETUP_MODE` | `best_effort` | `best_effort` or `strict`. |
| `DOTFILES_SYSTEM_UPGRADE` | `1` | Set to `0` to skip the system package refresh; equivalent to `--no-system-upgrade`. |
| `DOTFILES_DESKTOP` | detected | `gnome`, `kde`, or `none`; equivalent to `--desktop`. Read by `scripts/detect-desktop.sh`, which both `bootstrap.sh` and the playbook run in the same environment, so the two agree whether the value was set or detected. |
| `DOTFILES_CHEZMOI_DIR` | `~/.local/share/chezmoi` | Chezmoi source directory. Exported by bootstrap for the playbooks. |
| `DOTFILES_PROGRESS` | `1` | Set to `0` to turn off the progress bar that `bootstrap.sh` and `bootstrap.ps1` keep on the last terminal row. It is already off when output is not a terminal (or, on Windows, the host has no VT support) or in lightweight CI mode. |
| `DOTFILES_CI` | unset | Lightweight CI mode. Enables `--platform`, skips chezmoi self-upgrade, makes `chezmoi init` non-interactive, skips unstable upstream installers and the mise tool lists, and leaves this machine's desktop settings, panels and swap untouched (the report lists them under skipped). |
| `CHEZMOI_GPG_RECIPIENT` | none | GPG recipient for encrypted chezmoi files. Read by `home/.chezmoi.toml.tmpl`; when set, the first-run prompt for it is skipped. |
| `DOTFILES_BOOTSTRAP_OUTCOMES_FILE` | set by bootstrap | Internal. Path of the JSON-lines file in which `bootstrap.sh` records the outcome of each prerequisite step; `setup_outcome` merges it into the report. |

### Privileged setup (Linux and macOS)

| Variable | Default | Description |
| :--- | :--- | :--- |
| `DOTFILES_SUDO_PASSWORD_FILE` | none | File holding the sudo password for non-interactive runs; `bootstrap.sh` validates it and passes it to the playbook as `--become-password-file`; privileged tasks use Ansible `become`, so a playbook run by hand needs that flag (or passwordless sudo) as well. Without it, and without passwordless sudo, `bootstrap.sh` prompts once on Linux and macOS. On Linux a missing or rejected password stops the run, and preflight fails with an explicit message rather than hanging. On macOS only the `shell` feature needs sudo (to register the Homebrew bash in `/etc/shells` and change the login shell): a non-administrator account, a run without a terminal, or CI without passwordless sudo continues with a warning and that feature is reported as failed. |

### Low-memory machines

Low-memory setup turns on automatically on Linux at or below the memory threshold. It prepares swap when needed and asks package, npm, and external installers to do less work in parallel.

| Variable | Default | Description |
| :--- | :--- | :--- |
| `DOTFILES_LOW_MEMORY` | `auto` | `1`/`true`/`yes` forces it on, `0`/`false`/`no` forces it off, `auto` decides from total RAM. |
| `DOTFILES_LOW_MEMORY_THRESHOLD_MB` | `4096` | RAM at or below which `auto` turns low-memory setup on. |
| `DOTFILES_SWAPFILE_SIZE_MB` | 4096 at 2 GB RAM or less, otherwise 2048 | Size of the swapfile to create. |
| `DOTFILES_MIN_SWAP_MB` | same default as above | Swap total considered sufficient, below which a swapfile is created. |

### Upstream endpoints (tests only)

The install scripts read their upstream base URLs from the environment so the regression tests can point them at a local fixture. Leave them unset on a real machine.

| Variable | Default | Read by |
| :--- | :--- | :--- |
| `DOTFILES_GITHUB_API` | `https://api.github.com` | `scripts/nerd-font-install.sh`, `scripts/plasma-addons-install.sh` |
| `DOTFILES_GITHUB_WEB` | `https://github.com` | `scripts/plasma-addons-install.sh` |
| `DOTFILES_GITHUB_RAW` | `https://raw.githubusercontent.com` | `scripts/plasma-addons-install.sh` |
| `DOTFILES_KDE_STORE_API` | `https://api.kde-look.org/ocs/v1` | `scripts/plasma-addons-install.sh` |

CI detection is also read from `GITHUB_ACTIONS` and `CI`, which mark the run as an automation environment (setup mode comes only from the flags and `DOTFILES_SETUP_MODE`).

## Profile file format

`ansible/vars/profiles/<name>.yml`. All three keys are required; preflight rejects a profile missing `supported_platforms` or `features`.

```yaml
---
profile_name: work                     # human-facing label, carries no behavior
supported_platforms:                   # the run fails if the current platform is not listed
  - ubuntu
  - fedora
  - arch
  - macos
features:                              # explicit: there are no hidden defaults
  - core_cli
  - devtools
  - docker_desktop
```

Nothing else in the file is read. `features` is the only source of truth: roles ask `'docker_desktop' in features`, never a derived flag.

## Package set file format

`ansible/vars/package_sets/<platform>.yml`. Data only: package names grouped by feature and then by installer type. No conditionals, repositories, scripts, or services - those belong in a feature role.

```yaml
---
platform: ubuntu
package_family: apt

package_sets:
  core_cli:
    apt:
      - git
      - curl
  desktop_base:
    apt:
      - flatpak
    flatpak:
      - com.visualstudio.code
```

Installer types by platform:

| Platform | Package family | Installer keys |
| :--- | :--- | :--- |
| `ubuntu` | `apt` | `apt`, `flatpak` |
| `fedora` (also Fedora rebuilds such as Nobara) | `dnf` | `dnf`, `flatpak` |
| `arch` | `pacman` | `pacman`, `flatpak` |
| `macos` | `brew` | `brew`, `cask` |

## Chezmoi setup data

Generated before `chezmoi apply` and passed with `--override-data`:

| Key | Example |
| :--- | :--- |
| `dotfiles_profile` | `personal` |
| `dotfiles_platform` | `ubuntu` |
| `dotfiles_desktop` | `kde` (`gnome`, `kde`, `other`, or `none`; always `none` on macOS) |
| `dotfiles_features` | `["core_cli", "desktop_base", ...]` |

`chezmoi init` also stores `dotfiles_features` in the chezmoi config, read from the selected profile's `features` list, so it is available on a plain `chezmoi apply`; the setup run's `--override-data` wins when both exist. Read the keys defensively anyway:

```text
{{ $features := default (list) (get . "dotfiles_features") }}
{{ if has "desktop_base" $features }}...{{ end }}
```

Prefer platform, desktop, and feature checks over `dotfiles_profile`. Branching on a profile name means every new profile requires editing the template. Outside a setup run `dotfiles_desktop` is absent; a template that needs it can run the same detector, which answers in the same vocabulary: `default (output "bash" (joinPath .chezmoi.sourceDir ".." "scripts" "detect-desktop.sh") | trim) (get . "dotfiles_desktop")`.

## Playbook variables

| Variable | Set by | Meaning |
| :--- | :--- | :--- |
| `dotfiles_platform` | platform playbook | Name, package family, system, distribution, version, architecture, Ubuntu codename. |
| `platform_package_data` | platform playbook | The one package set loaded for this run. |
| `features` | profile file | Selected feature names. |
| `dotfiles_setup_mode` | flag or env | `best_effort` or `strict`. |
| `dotfiles_automation` | `common.yml` | True in CI or when `GITHUB_ACTIONS`/`CI` is set. |
| `dotfiles_container_ci` | `common.yml` | Automation running inside a container, where some desktop installers cannot work. |
| `dotfiles_low_memory_setup` | `common.yml` | Whether low-memory behavior is active. |
| `dotfiles_desktop` | `common.yml` | `gnome`, `kde`, `other`, or `none`, from `scripts/detect-desktop.sh` (or `DOTFILES_DESKTOP`). `none` on macOS. Selects which desktop settings role `desktop_base` runs. |
| `dotfiles_desktop_detail` | `common.yml` | The evidence the desktop was detected from, for the report (`XDG_CURRENT_DESKTOP=KDE`, `gnome-shell is running`, ...). |
| `dotfiles_feature_execution_order` | `profile_preflight` | The fixed order feature roles run in. A role missing from this list never runs. |
| `dotfiles_known_mise_tool_lists` | `profile_preflight` | Feature names that have a `home/dot_config/mise/conf.d/<feature>.toml`, accepted as implementations alongside package-set keys and role directories. |
| `dotfiles_mise_environment` | `mise_tools` | Environment for every mise command: `MISE_YES=1`, `~/.local/bin` on `PATH`, `GITHUB_TOKEN` when set, `MISE_JOBS=1` in low-memory mode. |
| `dotfiles_mise_missing_tools_before`, `dotfiles_mise_outdated_tools_before` | `mise_tools` | Tool names from `mise ls --missing --json` and `mise outdated --json` captured before `mise install` and `mise upgrade`; the two commands report `changed` when the matching list was non-empty. |
| `dotfiles_verified_mise_tool_lines`, `dotfiles_missing_mise_tool_names` | `setup_outcome` | Installed tools with versions (from `mise ls --json`) and tools still missing (from `mise ls --missing --json`), for the report. |
| `dotfiles_setup_failures` | `execution.yml`, roles, bootstrap handoff | Failures collected for the final report, each with `phase`, `name`, `task`, and `error`. |
| `dotfiles_setup_aborted` | `common.yml` | True when a failure stopped the run (strict mode, preflight, or an error no best-effort wrapper caught); the report names it and the play still fails. |

## Desktop settings

Desktop settings apply on Linux when a profile selects `desktop_base`, for the desktop that `scripts/detect-desktop.sh` detects:

| Result | Meaning | What `desktop_base` does |
| :--- | :--- | :--- |
| `gnome` | a GNOME session (Shell, Classic, Flashback) is running, or is the only installed desktop | `gnome` role: dconf entries from `home/.chezmoidata/gnome_dconf.yaml`, then `scripts/gnome-extensions-sync.sh apply` for `desktop_environment/gnome/` - both only inside a running GNOME session, since dconf needs the session bus |
| `kde` | a KDE Plasma session is running, or is the only installed desktop | `kde` role: `scripts/kde-settings-sync.sh apply` for `desktop_environment/kde/settings/`, with or without a running session |
| `other` | some other desktop is running or installed | nothing; recorded as skipped in the report |
| `none` | no session and no GNOME or Plasma session installed, or both installed and neither running, or `DOTFILES_DESKTOP=none` | nothing; recorded as skipped in the report |

Detection order: `DOTFILES_DESKTOP`; the session environment (`XDG_CURRENT_DESKTOP`, `XDG_SESSION_DESKTOP`, `DESKTOP_SESSION`, `KDE_FULL_SESSION`); session processes owned by the current user (`gnome-shell`, `plasmashell`, `kwin_wayland`, `kwin_x11`); the session files in `/usr/share/wayland-sessions` and `/usr/share/xsessions`. A running session always beats an installed one, and two running or two installed desktops are never resolved by guessing. `./scripts/detect-desktop.sh --explain` prints the result and the evidence on two lines.

### `scripts/gnome-extensions-sync.sh`

`capture`, `apply`, `diff`, `check`. Stores `desktop_environment/gnome/extensions.dconf` (a `dconf dump` of `/org/gnome/shell/extensions/`, minus the keys extensions rewrite on their own) and `desktop_environment/gnome/extensions.yaml` (enabled, disabled, user-installed and distro-installed extension UUIDs). `apply` downloads missing extensions.gnome.org extensions for the running Shell version, loads the settings, then enables the ones that are present.

### `scripts/kde-settings-sync.sh`

`capture`, `apply`, `diff`, `check`. Stores one file per tracked KDE config file in `desktop_environment/kde/settings/` - `kdeglobals`, `kwinrc`, `kwinrulesrc`, `kglobalshortcutsrc`, `kxkbrc`, `kcminputrc`, `powerdevilrc`, `knighttimerc`, `kscreenlockerrc`, `ksmserverrc`, `plasma-localerc`, `plasmarc`, `plasmanotifyrc`, `krunnerrc`, `klipperrc`, `dolphinrc`, `konsolerc`, `baloofilerc`, plus any file already present in the directory. The format is KConfig's own INI, including its escaping (`\t` for a tab, `\\` for a backslash) and nested group headers (`[Containments][2][Applets][23]`); `#` lines are comments.

`capture` drops the runtime state KDE keeps in those files - `[$Version]` update stamps, window and dialog geometry (the rest of `[MainWindow]` and the dialog groups, such as `MenuBar` or `Show hidden files`, is kept), saved sessions, virtual desktop and tiling UUIDs, the Xwayland scale derived from the display configuration, colour scheme hashes, activity shortcuts, notification "seen" flags - and keeps only the global shortcuts whose active binding differs from the default. In `kdeglobals`, colours are kept only when `[General] ColorScheme` names a scheme the user chose; colours a distro installed through its config cascade without naming the scheme are left out. A stored file with no counterpart on the machine is kept, so `apply` before `capture` if you edited a stored file by hand. `apply` writes every stored entry that differs, one `kwriteconfig6 --notify` call each (Plasma 5 machines use `kwriteconfig5`), leaves every other key in the live file alone, and asks KWin to reload when `kwinrc` changed; global shortcuts, power management, and the session itself pick the change up at the next login. `check` exits 0 when every stored entry matches the live file, or failing that the value `kreadconfig6` resolves through KDE's config cascade, which is what keeps the Ansible run idempotent.

Not captured by this script: the panel layout (`plasma-org.kde.plasma.desktop-appletsrc`, `plasmashellrc` - tied to activity and screen identifiers), which `scripts/plasma-panels-sync.sh` captures through the plasmashell scripting API instead, and the display layout (`kwinoutputconfig.json`, `kscreen/` - hardware serials), which is not captured at all. `home/.chezmoiignore` guards those, and every rc file the script tracks, against an accidental `chezmoi add`, because KDE replaces a symlinked rc file with a plain file on its first save.

## Tool versions

Every install path resolves the latest release at run time; no installer pins a tool version. How each surface gets there:

| Surface | How the latest version is chosen |
| :--- | :--- |
| System packages (`apt`, `dnf`, `pacman`), Homebrew, Flatpak | Package manager `latest` state, so re-running bootstrap upgrades what is already installed. |
| mise tool lists (`home/dot_config/mise/conf.d/*.toml`: lazygit, fd, bat, eza, zoxide, superfile, yazi, Starship, Playwright, the Bitwarden CLI, llmfit, claude, codex, opencode, pi, herdr, agy, paseo) | Every entry is requested as `"latest"` and there is no lockfile. `mise install` fetches the newest release of a missing tool and `mise upgrade` moves installed ones forward, both on every run, on every platform (`mise_tools` on Linux and macOS, `bootstrap.ps1` on Windows). Most names resolve to the aqua registry, which verifies checksums, cosign signatures and SLSA provenance where the publisher provides them; `npm:` entries need `node` on `PATH` (the `devtools` feature). mise itself comes from the Arch package, Homebrew, winget, or, on Ubuntu and Fedora, the `mise.run` installer (regenerated by upstream per release), which is run only when `~/.local/bin/mise` is absent or its version differs from the one upstream publishes at `https://mise.jdx.dev/VERSION`; the step is reported as changed only when the binary's digest changed. |
| winget (Windows) | `winget import --ignore-versions`, which installs missing packages and upgrades installed ones. Node is installed from the `OpenJS.NodeJS.LTS` channel on purpose (newest LTS rather than Node current). winget publishes Python as one package id per minor version (`Python.Python.3.x`); the package data names `Python.Python.3` and `bootstrap.ps1` resolves it to the newest minor id winget offers at run time (`Resolve-WingetPackageIds`), so no Python version is spelled out anywhere. |
| Kiro, Docker Desktop (Linux) | The installed version is compared with the upstream release feed (GitHub API, Kiro's metadata, Docker's appcast) on every run and the package is downloaded again only when it differs. Docker Desktop for Linux has no in-app updater, so this is the only thing that keeps it current. The appcast also names the build number; the package is downloaded from that build's directory and checked against the SHA-256 in the `checksums.txt` Docker publishes next to it, and the install is refused when the checksum cannot be read. Docker's apt repository is asked at run time (`dists/` on `download.docker.com`) which Ubuntu releases it serves. |
| JetBrains Toolbox, chezmoi | Downloaded from the vendor's permanent "latest" URL on every run. |
| Warp, Ghostty, VirtualBox | Vendor or distro repository; the package manager picks the newest build. On Ubuntu (amd64 only; preflight rejects the `virtualbox` feature on other architectures, as on Arch) VirtualBox comes from Oracle's repository: the newest release line Oracle publishes for this Ubuntu codename is installed (the `LATEST.TXT` line when the repository carries it, otherwise the newest `virtualbox-X.Y` it offers). The archive package is used only when Oracle has no build for the codename and nothing from Oracle is installed yet; an existing Oracle install is never replaced, whether the repository is unreachable or the codename is not published yet. |
| droid (`ai_clis`, `home/.chezmoidata/ai-clis.yaml`) | The vendor's installer script, which is regenerated per release and fetches that build; skipped in automation. `home/dot_config/starship.toml` is managed but intentionally holds only the schema line: Starship's built-in default prompt is the intended config, and the file exists so Nobara's `/etc/profile.d` hook does not copy its own theme into place when it finds no config. |
| Ghostty themes (`home/.chezmoiscripts/`) | The Fedora/Nobara `ghostty` package ships no `/usr/share/ghostty/themes`, so `theme = ...` in `home/dot_config/ghostty/config` fails to resolve. `run_once_after_install_ghostty_themes.sh.tmpl` runs once per machine, does nothing when a Ghostty resources directory already carries themes, and otherwise unpacks the ghostty themes from the default branch of `mbadolato/iTerm2-Color-Schemes` into `~/.config/ghostty/themes`. Themes chezmoi already manages there are never overwritten. |
| Login shell (macOS) | The `shell` feature uses the Homebrew `bash` (kept current by the brew pass) as the login shell and falls back to `/bin/bash` only when it is missing. `bootstrap.sh` also runs `brew upgrade ansible` before the playbook so Ansible itself stays current. |
| opencode MCP servers | Runtime configuration rather than an install path: `home/dot_config/opencode/opencode.jsonc.tmpl` pins `semble[mcp]==0.5.3` on purpose so the editor starts the same server offline; bump it deliberately. |

`test/upstream_installers_latest.sh` fails if any installer URL in `home/.chezmoiscripts/`, the `mise` role or `home/.chezmoidata/ai-clis.yaml` carries a version or a checksum pin, then downloads each installer and fails if it has stopped resolving the current release (`mise.run` is compared with the version upstream publishes; other installers must look up `releases/latest` or embed a vendor-regenerated version). `test/mise_tool_lists.sh` checks that every mise tool list is named after a selected feature, requests only `"latest"`, and is managed by chezmoi only when both `mise` and that feature are selected. `test/ci_bootstrap_regressions.sh` rejects GitHub release download URLs (`releases/download/vX.Y...`) that hardcode a version, and Ansible regex filters written with doubled backslashes (which never match inside folded scalars).

## Output

| Path | Contents |
| :--- | :--- |
| `~/.dotfiles_setup_report.md` | The setup outcome report, in Markdown: a header with date, profile, platform, desktop (Linux), mode, and result; an Errors section quoting every skipped (or aborting) failure; entries not detected afterwards; entries skipped intentionally; verified entries grouped by installer; completed bootstrap steps and playbook phases; and how to re-run. Written on every run, by `bootstrap.sh` itself when Ansible never produces one. |
| `~/.config/chezmoi/chezmoi.toml` | Answers to the first-run prompts: Git identity, GPG recipient, SSH choices, profile. |
| `~/.gitconfig.local` | Generated Git identity. Overwritten on every apply - put hand-maintained settings in `~/.gitconfig.machine` instead. |

## Testing

```sh
./test/test_harness.sh          # shellcheck, yamllint, ansible-lint, Ansible syntax checks, bootstrap, desktop detection, KDE and GNOME sync, setup mode phases, feature data, launchers, upstream installer and mise tool list checks, chezmoi dry run
./bootstrap.sh --profile personal --strict
```

The harness needs chezmoi on `PATH`. ShellCheck, yamllint, ansible-lint and the Ansible syntax checks run only when those tools are available (`.yamllint` and `.ansible-lint` at the repository root hold their configuration); the upstream installer checks need network access to GitHub for their live part and skip it without it.
