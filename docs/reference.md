# Reference

Flags, environment variables, and file formats. See [Architecture](architecture.md) for what these things do to a run.

## bootstrap.sh (Linux and macOS)

```sh
./bootstrap.sh [--profile personal|work] [--platform ubuntu|fedora|arch|macos] [--best-effort|--strict]
```

| Flag | Default | Description |
| :--- | :--- | :--- |
| `--profile <name>` | `DOTFILES_PROFILE`, or prompt | Which profile to install. Accepted values are `personal` and `work`, validated in `bootstrap.sh`, `bootstrap.ps1`, and `home/.chezmoi.toml.tmpl` (new profiles must be added to all three). |
| `--platform <name>` | detected from the OS | Override platform detection. **Rejected unless `DOTFILES_CI=1`** - a real machine must not be able to lie about its OS. |
| `--best-effort` | this is the default | Skip a failing step and keep going, recording every skipped failure in the final report. Applies to the bootstrap prerequisite steps as well as package installs, feature roles, each `chezmoi` script, and services. |
| `--strict` | | Stop at the first failure. Use this while developing. The report still records where the run stopped. |

The script detects the OS, maps it to a platform, installs chezmoi, git, Ansible, and the required collections, then runs exactly one playbook: `ansible/playbooks/<platform>.yml`. On macOS, Homebrew must already be installed - without it the first step that needs a package (usually installing Ansible) aborts the run, and the report says so.

Prerequisite steps that the rest of the run cannot work without stop the run even in best-effort mode: installing chezmoi (after the installer script, a direct GitHub release download, and the distro package manager have all been tried), cloning the repository, installing Ansible, and a required Ansible collection that is missing. Everything else (system package refresh, curl, git, chezmoi self-upgrade, `chezmoi init` from a checkout, refreshing the repository, refreshing collections from Galaxy) is skipped on failure and reported.

On Ubuntu, a `curl` that resolves to the Snap build is replaced with the native package before anything is downloaded; Snap confinement breaks upstream installer scripts that write to `/tmp`.

Exit status: `0` when the playbook finished, even with skipped failures (read the report); non-zero when a critical step or strict mode stopped the run.

Distro mapping: `ubuntu` to `ubuntu`, `fedora` to `fedora`, `arch` and `manjaro` to `arch`, Darwin to `macos`. Anything else fails early with an explicit message.

## bootstrap.ps1 (Windows)

```powershell
.\bootstrap.ps1 [-ProfileName personal|work] [-SetupMode best_effort|strict]
```

Windows uses winget and PowerShell rather than Ansible. It shares the profile and setup-mode vocabulary but not the playbook structure. `winget` must be available (it ships with App Installer); the script fails early without it. The chosen profile is cached in `~/.dotfiles_profile` and offered as the default on later runs.

## Environment variables

### Common

| Variable | Default | Description |
| :--- | :--- | :--- |
| `DOTFILES_REPO` | none | Repository to clone. Required when running a downloaded bootstrap script; ignored when running from a checkout. |
| `DOTFILES_PROFILE` | none | Profile to use, equivalent to `--profile`. |
| `DOTFILES_SETUP_MODE` | `best_effort` | `best_effort` or `strict`. |
| `DOTFILES_CHEZMOI_DIR` | `~/.local/share/chezmoi` | Chezmoi source directory. Exported by bootstrap for the playbooks. |
| `DOTFILES_PROGRESS` | `1` | Set to `0` to turn off the progress bar that `bootstrap.sh` and `bootstrap.ps1` keep on the last terminal row. It is already off when output is not a terminal (or, on Windows, the host has no VT support) or in lightweight CI mode. |
| `DOTFILES_CI` | unset | Lightweight CI mode. Enables `--platform`, skips chezmoi self-upgrade, makes `chezmoi init` non-interactive, and skips unstable upstream installers. |
| `DOTFILES_BOOTSTRAP_OUTCOMES_FILE` | set by bootstrap | Internal. Path of the JSON-lines file in which `bootstrap.sh` records the outcome of each prerequisite step; `setup_outcome` merges it into the report. |

### Linux privileged setup

| Variable | Default | Description |
| :--- | :--- | :--- |
| `DOTFILES_SUDO_PASSWORD_FILE` | none | File holding the sudo password for non-interactive runs. Without it, and without passwordless sudo, preflight fails with an explicit message rather than hanging. |

### Low-memory machines

Low-memory setup turns on automatically on Linux at or below the memory threshold. It prepares swap when needed and asks package, npm, and external installers to do less work in parallel.

| Variable | Default | Description |
| :--- | :--- | :--- |
| `DOTFILES_LOW_MEMORY` | `auto` | `1`/`true`/`yes` forces it on, `0`/`false`/`no` forces it off, `auto` decides from total RAM. |
| `DOTFILES_LOW_MEMORY_THRESHOLD_MB` | `4096` | RAM at or below which `auto` turns low-memory setup on. |
| `DOTFILES_SWAPFILE_SIZE_MB` | 4096 at 2 GB RAM or less, otherwise 2048 | Size of the swapfile to create. |
| `DOTFILES_MIN_SWAP_MB` | same default as above | Swap total considered sufficient, below which a swapfile is created. |

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

Profiles may also set compatibility variables consumed by older roles, but the `features` list is the source of truth - `common.yml` derives `gnome_settings_enabled`, `install_ai_clis`, `install_docker`, `install_jetbrains_toolbox`, and `linux_native_apps` from it.

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
| `fedora` | `dnf` | `dnf`, `flatpak` |
| `arch` | `pacman` | `pacman`, `flatpak` |
| `macos` | `brew` | `brew`, `cask` |

## Chezmoi setup data

Generated before `chezmoi apply` and passed with `--override-data`:

| Key | Example |
| :--- | :--- |
| `dotfiles_profile` | `personal` |
| `dotfiles_platform` | `ubuntu` |
| `dotfiles_features` | `["core_cli", "desktop_base", ...]` |

Read them defensively in templates, since `chezmoi` commands run outside a setup run will not have them:

```text
{{ $features := default (list) (get . "dotfiles_features") }}
{{ if has "desktop_base" $features }}...{{ end }}
```

Prefer platform and feature checks over `dotfiles_profile`. Branching on a profile name means every new profile requires editing the template.

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
| `dotfiles_feature_execution_order` | `profile_preflight` | The fixed order feature roles run in. A role missing from this list never runs. |
| `dotfiles_setup_failures` | `execution.yml`, roles, bootstrap handoff | Failures collected for the final report, each with `phase`, `name`, `task`, and `error`. |
| `dotfiles_setup_aborted` | `common.yml` | True when a failure stopped the run (strict mode, preflight, or an error no best-effort wrapper caught); the report names it and the play still fails. |

## Output

| Path | Contents |
| :--- | :--- |
| `~/.dotfiles_setup_report.md` | The setup outcome report, in Markdown: a header with date, profile, platform, mode, and result; an Errors section quoting every skipped (or aborting) failure; entries not detected afterwards; entries skipped intentionally; verified entries grouped by installer; completed bootstrap steps and playbook phases; and how to re-run. Written on every run, by `bootstrap.sh` itself when Ansible never produces one. |
| `~/.config/chezmoi/chezmoi.toml` | Answers to the first-run prompts: Git identity, GPG recipient, SSH choices, profile. |
| `~/.gitconfig.local` | Generated Git identity. Overwritten on every apply - put hand-maintained settings in `~/.gitconfig.machine` instead. |

## Testing

```sh
./test/test_harness.sh          # shellcheck, Ansible checks, bootstrap regressions, chezmoi dry run
./bootstrap.sh --profile personal --strict
```

The harness needs chezmoi on `PATH`. ShellCheck and Ansible checks run only when those tools are available.
