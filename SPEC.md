# Dotfiles Setup Automation Spec

## Status

This is a discovery draft based on the current repository state. It is not final yet.

The goal of this document is to make the migration from the current `chezmoi`-driven setup to a cross-platform automation flow explicit before implementation starts.

## Current Repository State

This repo already automates a meaningful part of machine setup through `chezmoi`:

- Bootstraps `chezmoi` on Linux, macOS, and Windows
- Applies dotfiles in `symlink` mode
- Installs system packages on Linux with `dnf`, `apt`, or `pacman`
- Installs packages on macOS with Homebrew
- Installs packages on Windows with `winget`
- Installs Linux GUI apps with Flatpak
- Installs runtimes and developer tools via `mise`
- Applies GNOME `dconf` settings on supported Linux desktops
- Enables a user `systemd` service for `auto-headphone-switch`
- Installs optional AI CLIs

The repo is not just storing dotfiles. It already acts as a machine bootstrap system.

## Problem Statement

I have multiple devices across Linux, macOS, and Windows.

Each device does not need the exact same setup.

I want a setup flow that:

- works across all target operating systems
- lets me choose a setup at install time
- supports different device types and roles
- keeps the setup maintainable as the number of devices grows

## Primary Goal

Introduce Ansible as the main orchestration layer for machine setup, while preserving or intentionally replacing the parts of the current `chezmoi` workflow that are already working well.

## Confirmed Decisions

The following decisions are now agreed:

- `chezmoi` stays as the dotfile manager
- Ansible becomes the orchestration layer
- installer flow uses one selected profile
- Windows support is basic first, with fuller parity later
- the chosen profile should be saved per machine for re-runs
- saved machine state should live in Ansible facts/cache
- reruns should show the current saved profile and ask whether to continue
- `work` should avoid auto-configuring custom work dotfiles; work-specific configuration can be done manually
- Windows v1 should include `winget` + `chezmoi apply` + some basic shell/dev setup
- GNOME settings should run only when the selected profile needs them and GNOME is detected
- a hidden minimal/base mode is not required
- `chezmoi` should keep prompting for Git identity
- `work` should install programming languages, AI CLI tools, and IDE tooling
- `work` should not install `Discord` or `Telegram`
- `work` should still run `chezmoi apply` for shared/common dotfiles
- the `dev` option is removed entirely
- `work` should install `Chrome`
- `work` IDEs should include `VS Code`, `Neovim`, and `JetBrains Toolbox`
- `work` AI CLIs should include `codex`, `claude`, `agy`, `droid`, and `opencode`
- `work` should use the same shell setup as `personal`
- `personal` should install `Obsidian`, `Postman`, `Docker`, `Ghostty`, `Chrome`, and `VS Code`
- `personal` should keep the current Windows GUI app set from the existing `winget` list
- Linux `personal` should keep GNOME settings enabled by default when GNOME is detected
- `work` should install the same GUI apps as `personal` except `Discord` and `Telegram`
- Linux `work` should also apply the default GNOME settings when GNOME is detected
- package definitions should be separated by profile
- `IntelliJ IDEA` should not be installed in either `personal` or `work`
- `JetBrains Toolbox` should be installed instead of `IntelliJ IDEA`
- AI CLI tools should be installed for both `personal` and `work`
- `JetBrains Toolbox` should be installed for both `personal` and `work`
- `.chezmoidata/packages.yaml` should use separate top-level groups for `personal` and `work`
- AI CLI installation should be automatic based on the selected profile
- `JetBrains Toolbox` may use a download-script or manual-installer flow when no clean package-manager package exists
- package data should use a `common` base plus `personal` and `work` overrides
- the installer should not ask for an elevation password repeatedly during package installation
- on Unix-like systems, elevation should be requested once at the start of the run and reused for the rest of the setup
- the installer should prompt for elevation once at the start of install, then avoid further password prompts during that run
- package installation fallback should be:
  package manager first, then official install/download script, then manual install instructions
- `work` should install `Docker`
- `work` should install `Ghostty`
- reruns with a saved profile should prompt like `Current profile is work. Continue? [Y/n]`
- if the user answers no to the saved-profile prompt, only then should the installer show the profile menu again

## Recommended Direction

### Keep `chezmoi` for dotfiles

Recommended default:

- `chezmoi` stays responsible for dotfiles rendering and symlink management
- Ansible becomes the orchestration layer that installs packages, selects profiles, applies OS-specific tasks, and optionally calls `chezmoi`

Why this is the safest direction:

- the repo already uses `chezmoi` well
- `chezmoi` is strong at dotfiles templating and file targeting
- Ansible is stronger at orchestration, conditional execution, menus, variables, roles, and profile composition
- replacing both orchestration and dotfiles management at the same time would create more migration risk

### Use profiles instead of one fixed setup

The install menu should probably be profile-based, not package-manager-based.

Base profiles:

- `personal`
- `work`

Each profile can combine reusable components such as:

- base CLI tools
- language runtimes
- desktop apps
- AI tools
- shell setup
- GNOME settings
- Docker setup
- SSH config

For this repo, the profile names should stay short and device-agnostic.

The OS-specific behavior should happen underneath the profile through Ansible conditionals, not by exposing many profile names to the menu.

Meaning of each choice:

- `personal`: includes the full personal setup you want on your own machine, including your full shell setup, curated apps, and GNOME settings on Linux when GNOME is detected
- `work`: includes the company-machine setup with the same general shell and GUI tooling as `personal`, but excludes `Discord` and `Telegram`, and includes programming languages, AI CLI tools, and IDE tooling

## Proposed Architecture

### Layer 1: Bootstrap

Small bootstrap entrypoints per platform:

- `bootstrap.sh` for Linux and macOS
- `bootstrap.ps1` for Windows

Bootstrap responsibilities:

- detect the current operating system automatically
- ensure Ansible is available
- if Ansible is missing on a new machine, install it before trying to run the playbook
- clone or update this repo
- launch the main playbook locally

Fresh-machine requirement:

- a brand-new machine must not require Ansible to already be installed manually
- the bootstrap entrypoint is responsible for checking for Ansible first
- if Ansible is not present, bootstrap installs it using the most appropriate method for that OS
- prefer the most stable installation method for Ansible on each OS
- only after Ansible is available should the main setup playbook execute

### Layer 2: Ansible Orchestration

Ansible becomes responsible for:

- detecting OS family and platform capabilities
- showing the user a menu of setup profiles for the current machine
- collecting install choices
- applying roles conditionally
- invoking `chezmoi` where needed

### Layer 3: Dotfiles

`chezmoi` remains responsible for:

- rendering templates
- symlink mode behavior
- per-user file placement
- prompts for values that belong in templated config, unless moved into Ansible variables

## Proposed Ansible Model

### Inventory Style

Likely local-only execution:

- connection: local
- machine setup runs on the current machine
- no remote server management is required for the first version

### Structure

A likely starting structure:

```text
ansible/
  playbooks/
    setup.yml
  roles/
    base
    packages
    mise
    flatpak
    gnome
    ai_tools
    docker
    shell
    chezmoi
  vars/
    profiles/
      personal.yml
      work.yml
```

### Profile Composition

Each profile should define:

- supported OS or OS family
- enabled roles
- package groups
- desktop features
- optional apps
- whether `chezmoi apply` should run
- whether prompts are interactive or non-interactive

Day-one profiles:

- `personal`
- `work`

These names should stay stable across Linux, macOS, and Windows.

OS detection should happen before profile selection.

That means:

- the installer detects whether the current machine is Linux, macOS, or Windows
- the installer loads the matching platform rules
- the installer then shows the available profile choices
- after profile selection, Ansible runs only the tasks valid for that OS

## Menu / Selection Requirements

The installer should support one of these approaches:

### Option A: Interactive text menu

At install time:

- show available profiles
- let the user pick one profile

Pros:

- friendly for fresh installs
- matches the request closely

Cons:

- slightly more logic in bootstrap/playbook flow

### Option B: Command-line profile selection

Examples:

- `./bootstrap.sh --profile personal`
- `ansible-playbook ansible/playbooks/setup.yml -e profile=work`

Pros:

- simpler to automate
- easier to reuse in CI or on repeated rebuilds

Cons:

- less friendly for manual first-time setup

### Option C: Both

Recommended:

- interactive menu if no profile is provided
- non-interactive mode if `--profile` is provided

## Minimal Menu Requirement

The install menu should be kept as small as possible.

Day-one menu behavior:

1. Detect the current OS automatically
2. Ask for one profile for that machine:
   - `personal`
   - `work`
3. Save that choice in Ansible facts/cache
4. Reuse the saved choice on future runs unless the user explicitly changes it

The menu should still remain minimal:

- one profile question
- no extra bundle selection in version 1

## Installer Flow

The intended version 1 flow is:

1. User runs `bootstrap.sh` on Linux or macOS, or `bootstrap.ps1` on Windows
2. Bootstrap detects the current OS automatically
3. Bootstrap checks whether Ansible is installed
4. If Ansible is missing, bootstrap installs it first
5. Bootstrap starts the local Ansible setup flow
6. Ansible checks whether this machine already has a saved profile in facts/cache
7. If no saved profile exists, show the minimal setup menu:
   - `personal`
   - `work`
8. Save the selected profile
9. Apply the selected setup using OS-specific tasks for the detected platform
10. Run `chezmoi apply` as part of the setup flow

On Unix-like systems, the setup flow should validate elevated access once near the start so package tasks do not keep prompting for a password repeatedly.

If a saved profile already exists, version 1 should:

- show the current saved setup and ask whether to continue
- allow an explicit override such as `--profile work`
- avoid asking unnecessary questions after confirmation

## Configuration Model

The main configuration model should use named profiles.

### Named profiles

Examples:

- `personal`
- `work`

Best when:

- device setups are mostly known in advance
- you want fast repeatability

### Recommendation

Use only named profiles in version 1:

- `personal`
- `work`

If more variation is needed later, bundles or add-ons can be added in a future version.

## Cross-Platform Concerns

### Linux

Need to support:

- distro family detection
- package-manager differences
- optional GNOME-only tasks when both the profile requires them and GNOME is detected
- optional `systemd` user service setup
- Flatpak only where desired

### macOS

Need to support:

- automatic detection through bootstrap and Ansible facts
- Homebrew installation and bundle management
- macOS-only desktop apps
- skipping Linux-specific tasks cleanly

### Windows

Need to support:

- PowerShell bootstrap
- automatic detection through the Windows bootstrap entrypoint
- local Ansible execution strategy or delegated bootstrap approach
- `winget` package installation
- `chezmoi apply`
- some basic shell/dev setup
- Windows-safe handling for paths, shell config, and optional dotfiles application

## Windows Strategy

This decision is now settled for version 1.

Possible approaches:

### Option 1: Keep Windows mostly bootstrap-script driven

- PowerShell handles Windows package installation and local setup
- Ansible is used mainly for Linux and macOS

Pros:

- simpler and lower risk

Cons:

- less unified architecture

### Option 2: Use Ansible for Windows local provisioning too

- PowerShell bootstrap installs Ansible-compatible runtime if needed
- bootstrap then runs local Ansible tasks for Windows

Pros:

- one orchestration model across all platforms

Cons:

- more setup complexity on Windows

### Version 1 Decision

Start with:

- Ansible as the main orchestrator for Linux and macOS
- Windows supported through the existing basic bootstrap-first approach
- full local-Ansible parity on Windows deferred to a later phase

Version 1 interpretation:

- Linux and macOS bootstrap should install Ansible automatically when missing
- Windows may continue using the simpler bootstrap-first flow until full local-Ansible parity is implemented
- if Windows later moves to full Ansible parity, the same bootstrap-first Ansible installation requirement should apply there too

## Migration Strategy

Recommended incremental path:

1. Keep current `chezmoi` structure intact
2. Add Ansible alongside the existing scripts
3. Move package installation into Ansible first
4. Move role-based setup into Ansible next
5. Keep `chezmoi apply` as a step inside Ansible
6. Retire redundant `chezmoiscripts` only after the Ansible flow is stable

This reduces the chance of breaking current working setups.

## Bootstrap Requirement

The bootstrap entrypoint must be able to run successfully on a fresh machine.

That means:

- do not assume Ansible is already installed
- detect whether Ansible exists before invoking any playbook
- install Ansible automatically when it is missing
- choose the most stable installation path per OS rather than the most customized path
- keep the bootstrap layer small and reliable so it can prepare the machine for the main setup flow

## Elevation Requirement

Package installation often needs elevated privileges on Linux and sometimes on macOS.

Version 1 should optimize for a smooth local install experience:

- do not prompt for the password on every package task
- request elevation once near the start of the setup run
- reuse that elevation state for the rest of the installation where possible
- structure Ansible tasks so privilege escalation is grouped cleanly instead of toggled constantly

For Unix-like systems, a likely implementation is:

- validate `sudo` once near the beginning of the run
- keep the `sudo` timestamp alive during the playbook
- run package-manager tasks with `become: true`

This requirement is about avoiding repeated prompts, not about forcing passwordless `sudo`.

## Saved Machine State

The selected profile should be persisted locally so repeated runs do not require re-selection.

Version 1 behavior:

- first run asks for a profile
- chosen setup is saved in Ansible facts/cache
- later runs show the current saved setup and ask whether to continue
- user can override the saved profile explicitly

Likely saved data:

- selected profile name

## Non-Goals For First Version

Unless explicitly requested, version 1 should avoid:

- replacing `chezmoi` completely
- remote fleet management
- secrets management redesign
- full enterprise Windows management complexity
- highly dynamic GUI menus

## Remaining Open Questions

Most major product decisions are now settled.

The remaining questions are implementation-level:

1. Which exact package identifiers should be used for `JetBrains Toolbox` on each platform?

2. What is the cleanest Ansible implementation for one-time elevation per run on Linux and macOS?

3. What exact `.chezmoidata/packages.yaml` schema should be used for `common`, `personal`, and `work` across Linux, Homebrew, Winget, and Flatpak sources?

## Initial Decisions From Repository Review

Based on the current repo, these assumptions seem reasonable unless you want otherwise:

- dotfiles should remain in this repo
- `chezmoi` should remain the dotfile manager
- package definitions should stay data-driven
- OS detection should be automatic
- interactive install should remain available
- AI CLI installation should be profile-driven and automatic
- GNOME customization should remain Linux- and desktop-specific
- the visible menu should stay limited to `personal` and `work`
- machine state should be stored in Ansible facts/cache
- `chezmoi` should keep prompting for identity values
- `work` should use the same shell setup as `personal`
- `work` should use the same GUI app set as `personal` except `Discord` and `Telegram`
- both `personal` and `work` should use `JetBrains Toolbox` instead of `IntelliJ IDEA`
- AI CLI tools should install for both profiles
- package data should use `common` plus top-level `personal` and `work` overrides
- elevation should prompt once at the start of install and not repeatedly during the run
- reruns should default to the saved profile and only reopen the menu if the user declines

## Next Discussion Goal

After your feedback, this spec should be tightened into:

- agreed profile model
- agreed Windows strategy
- agreed division of responsibility between Ansible and `chezmoi`
- agreed installer UX
- agreed migration milestones
