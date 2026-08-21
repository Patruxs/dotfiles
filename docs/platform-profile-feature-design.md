# Platform, Profile, and Feature Design

This design keeps each operating system isolated while avoiding duplicated profiles such as `ubuntu-personal`, `ubuntu-work`, and `ubuntu-server`.

## Goals

- Run only the setup needed for the current operating system.
- Keep profile files focused on machine purpose, not package-manager details.
- Let future profiles, such as `server`, reuse the Ubuntu platform setup without inheriting desktop tools.
- Fail before installing anything when a profile, platform, or feature is unsupported.
- Preserve existing personal and work behavior during migration.

## Core Model

Profiles select features:

```yaml
# ansible/vars/profiles/personal.yml
profile_name: personal
supported_platforms:
  - ubuntu
  - fedora
  - arch
  - macos
features:
  - core_cli
  - desktop_base
  - desktop_apps
  - devtools
  - npm_global_tools
  - ai_clis
  - docker_desktop
  - flatpak_apps
  - warp_terminal
  - ghostty_terminal
  - jetbrains_toolbox
  - virtualbox
  - kiro_ide
```

Platform setup translates features into OS-specific packages and installers:

```yaml
# ansible/vars/package_sets/ubuntu.yml
platform: ubuntu
package_family: apt

package_sets:
  core_cli:
    apt:
      - git
      - curl
      - wget
      - unzip
      - zsh
      - bash
      - neovim
      - tmux
      - btop
      - ripgrep
      - jq
      - bat
  devtools:
    apt:
      - nodejs
      - npm
      - python3
      - python3-pip
      - gcc
      - golang-go
      - gh
      - fzf
  docker_engine:
    apt:
      - docker.io
  webserver_nginx:
    apt:
      - nginx
```

Feature names are shared concepts. Package sets and feature roles implement those concepts for the selected platform.

## Target File Layout

```text
ansible/playbooks/
  ubuntu.yml
  fedora.yml
  arch.yml
  macos.yml
  common.yml

ansible/vars/profiles/
  personal.yml
  work.yml
  server.yml        # planned, not runnable until implementation

ansible/vars/package_sets/
  ubuntu.yml
  fedora.yml
  arch.yml
  macos.yml

ansible/roles/
  profile_preflight/
  package_installer/
  chezmoi/
  features/
    ai_clis/
    docker_desktop/
    flatpak_apps/
    ghostty_terminal/
    jetbrains_toolbox/
    kiro_ide/
    npm_global_tools/
    virtualbox/
    warp_terminal/
    webserver_nginx/

bootstrap.sh
bootstrap.ps1
```

Windows remains on `bootstrap.ps1` and winget for now. It can adopt the same profile and feature language later without being forced into the Unix/macOS Ansible flow.

## Playbook Shape

Each Unix/macOS platform has a standalone entrypoint. Bootstrap chooses exactly one.

```yaml
# ansible/playbooks/ubuntu.yml
---
- name: Ubuntu setup
  hosts: localhost
  connection: local
  gather_facts: yes

  vars:
    dotfiles_platform:
      name: ubuntu
      package_family: apt

  pre_tasks:
    - name: Load Ubuntu package set
      include_vars:
        file: "{{ chezmoi_dir }}/ansible/vars/package_sets/ubuntu.yml"
        name: platform_package_data

  tasks:
    - import_tasks: common.yml
```

`common.yml` owns the shared order:

```text
1. load selected profile
2. preflight validate platform/profile/features
3. generate Chezmoi setup data
4. install package-set entries
5. run selected feature roles that exist
6. apply Chezmoi
7. enable selected services
```

Profile feature order does not control execution order.

## Bootstrap Behavior

Normal use auto-detects the current platform:

```bash
./bootstrap.sh --profile personal
```

On Ubuntu this runs only:

```bash
ansible-playbook ansible/playbooks/ubuntu.yml -e profile=personal
```

A platform override is allowed only for CI/testing:

```bash
DOTFILES_CI=1 ./bootstrap.sh --platform ubuntu --profile personal
```

On real machines, an override that disagrees with the detected OS should fail.

## Preflight Validation

Before installing anything, setup validates:

- the detected platform maps to a known playbook
- the profile file exists
- the profile declares `supported_platforms`
- the current platform is allowed by the profile
- every selected feature has a package-set entry, a matching feature role, or both
- selected feature roles support the current platform/version/architecture

Unknown or unsupported selected features fail clearly.

## Feature Implementation Rules

A feature can be implemented in three ways:

- package-set only: `core_cli`
- feature-role only: `warp_terminal`
- both package-set and feature-role: `docker_desktop`

Feature role names match feature names exactly:

```text
feature: docker_desktop
role: ansible/roles/features/docker_desktop/
```

Package sets are data only. They contain direct package or app names grouped by installer type. Repositories, keys, scripts, downloaded archives, remotes, services, and conditionals belong in feature roles.

```yaml
package_sets:
  core_cli:
    apt:
      - git
      - curl
  desktop_apps:
    cask:
      - visual-studio-code
```

Flatpak apps use a feature role because Flathub remote setup is procedural.

## Planned Server Profile

The server profile is documented as a planned example, not implemented as a runnable profile yet.

```yaml
# planned ansible/vars/profiles/server.yml
profile_name: server
supported_platforms:
  - ubuntu
features:
  - core_cli
  - docker_engine
  - webserver_nginx
```

Initial server scope is minimal:

- install selected tools
- enable obvious services
- avoid desktop features
- avoid full security hardening, firewall policy, TLS certificates, reverse proxy config, and SSH hardening until those become explicit features

## Chezmoi Data

All profiles run `chezmoi apply`. Before applying, Ansible should generate setup data that Chezmoi templates can read:

```yaml
dotfiles_profile: personal
dotfiles_platform: ubuntu
dotfiles_features:
  - core_cli
  - desktop_base
  - docker_desktop
```

Templates should prefer feature and platform checks over profile-name checks. For example, desktop-only templates should check for `desktop_base` or another desktop feature instead of checking whether the profile is `personal` or `work`.

## Migration Checklist

1. Add feature lists to existing `personal` and `work` profiles.
2. Derive current compatibility vars from features, such as AI CLI toggles and Linux native app lists.
3. Add preflight validation for profile existence, supported platforms, and selected features.
4. Add standalone platform playbooks for Ubuntu, Fedora, Arch, and macOS.
5. Update `bootstrap.sh` to auto-detect the platform and choose exactly one playbook.
6. Add CI-only `--platform` override support.
7. Move package data from `.chezmoidata/packages.yaml` into per-platform package-set files.
8. Convert procedural installers into feature roles whose names match their feature names.
9. Generate Chezmoi setup data before `chezmoi apply`.
10. Guard platform-specific and feature-specific Chezmoi templates.
11. Add platform isolation regression tests.
12. Add the runnable `server` profile after the model is stable.
13. Remove old package-data compatibility once per-platform package sets are authoritative.

## Regression Tests

Implementation should prove:

- Ubuntu runs only `ansible/playbooks/ubuntu.yml`.
- Ubuntu loads only `ansible/vars/package_sets/ubuntu.yml`.
- Fedora, Arch, and macOS package sets are not loaded during Ubuntu setup.
- Unknown features fail before installation.
- Unsupported profile/platform combinations fail before installation.
- CI can use `--platform`; real machines cannot lie about their platform.
