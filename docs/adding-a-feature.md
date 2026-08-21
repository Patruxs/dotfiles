# Adding a Feature

Most contributions to this repository are one of four things: installing a new tool, adding a new profile, supporting a new platform, or managing a new config file. This is the checklist for each.

Read [Architecture](architecture.md) first if the words *profile*, *feature*, and *platform* do not yet mean something specific to you.

## Adding a tool or app

### Step 1: Decide if it needs a feature at all

Not everything deserves a new feature name. If the tool belongs to a capability that already exists, add it to that feature's package set and stop.

```yaml
# ansible/vars/package_sets/ubuntu.yml
package_sets:
  core_cli:
    apt:
      - git
      - curl
      - your-new-tool   # done
```

Create a new feature only when a profile should be able to select it independently.

### Step 2: Pick the name

Feature names are lowercase with underscores, and they describe the capability rather than the vendor's marketing. Two rules matter:

- **Same name on every platform.** `flatpak_apps` means the same thing whether or not the current OS has Flatpak. Never create `ubuntu_docker` or `macos_terminal`.
- **Be specific when alternatives exist.** `webserver_nginx`, not `webserver`. `docker_engine` and `docker_desktop` are separate features because one is for servers and one is a desktop app. If you find yourself wanting to add options to a feature, add a second feature instead.

### Step 3: Choose an implementation

Ask one question: *can the platform's package manager install this by name alone?*

**Yes - package set only.** Add the feature to every platform where it is supported. Package sets hold nothing but names grouped by installer type.

```yaml
# ansible/vars/package_sets/ubuntu.yml
package_sets:
  webserver_nginx:
    apt:
      - nginx
```

**No - you need a feature role.** Repositories, signing keys, downloaded archives, upstream install scripts, remotes, and services are all procedural, and all belong in a role. Create `ansible/roles/features/<feature_name>/tasks/main.yml`, where the directory name matches the feature name exactly - the preflight check finds implementations by listing that directory.

```yaml
# ansible/roles/features/your_feature/tasks/main.yml
---
- name: Install your feature on Linux
  include_tasks: "{{ chezmoi_dir }}/ansible/roles/linux_apps/tasks/linux-yourtool.yml"
  when:
    - dotfiles_platform.system == 'Linux'
    - not (dotfiles_ci | default(false))
```

Guard every task with the platforms it actually supports. A role that runs on a platform it was not written for is worse than one that is missing.

**Both.** A feature can have package-set entries *and* a role - `docker_desktop` installs its dependency packages from the package set and does the rest procedurally.

### Step 4: Register the role in the execution order

> [!IMPORTANT]
> A feature role does not run just because it exists. `ansible/roles/profile_preflight/tasks/main.yml` defines `dotfiles_feature_execution_order`, and `execution.yml` loops over exactly that list. A role missing from it is never executed, and nothing warns you.

```yaml
# ansible/roles/profile_preflight/tasks/main.yml
- name: Define known feature implementations
  set_fact:
    dotfiles_feature_execution_order:
      - desktop_base
      - shell
      - your_feature     # position matters: this is the real install order
      - ...
```

Place it after anything it depends on. Package-set-only features do not go in this list - they are installed by `package_installer` in step 3 of the run.

### Step 5: Declare where it cannot run

If the feature is unavailable on some version or architecture, say so in the unsupported-feature checks in `profile_preflight`, next to the existing `docker_desktop` and `kiro_ide` entries. Preflight then fails with a clear message before anything is installed, which is the behavior this project wants - an unsupported selection is an error, not a silent skip.

### Step 6: Select it in a profile

Features are opt-in. Nothing installs until a profile lists it.

```yaml
# ansible/vars/profiles/personal.yml
features:
  - core_cli
  - your_feature
```

### Step 7: Test

```sh
./test/test_harness.sh                    # fast checks: shellcheck, ansible, chezmoi dry run
./bootstrap.sh --profile personal --strict  # real run, fail fast on the first problem
```

Use `--strict` while developing. The default `best_effort` mode is right for real machines but will collect your failure into the final report and keep going, which is not what you want when you are trying to see a mistake.

## Adding a profile

1. Create `ansible/vars/profiles/<name>.yml` with `profile_name`, `supported_platforms`, and `features`. All three are required - preflight rejects a profile that omits `supported_platforms` or `features`.
2. List only the platforms the profile is genuinely meant for. A `server` profile that lists just `ubuntu` will fail clearly on a Mac instead of half-installing.
3. Add the profile name to every place that validates it - there are three: `bootstrap.sh` (the `--profile` case statement), `bootstrap.ps1` (the `Get-Profile` regex), and `home/.chezmoi.toml.tmpl` (which makes `chezmoi init` fail for unknown profiles). Missing one produces a confusing failure partway through a run.
4. Prefer feature checks over profile-name checks anywhere else. Profile names carry no behavior, and templates that branch on `personal` need editing every time a profile is added.

## Adding a platform

1. Create `ansible/vars/package_sets/<platform>.yml` with `platform`, `package_family`, and a `package_sets` mapping that covers the features you intend to support.
2. Create `ansible/playbooks/<platform>.yml` modeled on `ubuntu.yml`: define the `dotfiles_platform` facts, load that one package set into `platform_package_data`, and `import_tasks: common.yml`. Keep it thin - shared logic belongs in `common.yml`, not here.
3. Teach `detect_platform()` in `bootstrap.sh` to map the OS or distro to the new platform name.
4. Add the platform to the `supported_platforms` of every profile that should run on it.
5. Provide feature roles for any procedural features on that platform, or leave the feature out of that platform's package set so preflight reports it honestly.

## Adding a managed config file

Configuration is Chezmoi's job, not Ansible's.

```sh
chezmoi add ~/.config/yourtool/config
chezmoi diff
```

If the file should only exist on some machines, guard it with the setup data the run generates - `dotfiles_platform` and `dotfiles_features` - rather than `dotfiles_profile`:

```text
{{- if not (has "desktop_base" (default (list) (get . "dotfiles_features"))) }}
.config/yourtool/config
{{- end }}
```

## Before you open the pull request

- [ ] The feature name means the same thing on every platform.
- [ ] Package sets contain only package names, with no logic.
- [ ] The feature role directory name matches the feature name exactly.
- [ ] The role is registered in `dotfiles_feature_execution_order`.
- [ ] Unsupported platforms, versions, and architectures fail in preflight rather than mid-install.
- [ ] Re-running the setup changes nothing the second time.
- [ ] `./test/test_harness.sh` passes.
- [ ] No secrets, private keys, or machine-specific hostnames are included.

If your change alters one of these rules rather than following it, say why in the pull request and update [Why it works this way](architecture.md#why-it-works-this-way), so the next person inherits the reasoning and not just the rule.
