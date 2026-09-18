#!/usr/bin/env bash
# shellcheck disable=SC2016  # patterns below are literal grep needles, $ is intentional
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
packages_task="$repo_root/ansible/roles/package_installer/tasks/main.yml"
macos_packages_task="$repo_root/ansible/roles/package_installer/tasks/macos.yml"
mise_tools_task="$repo_root/ansible/roles/mise_tools/tasks/main.yml"
mise_feature_task="$repo_root/ansible/roles/features/mise/tasks/linux.yml"
windows_bootstrap="$repo_root/bootstrap.ps1"
common_playbook="$repo_root/ansible/playbooks/common.yml"
execution_playbook="$repo_root/ansible/playbooks/execution.yml"
ubuntu_playbook="$repo_root/ansible/playbooks/ubuntu.yml"
fedora_playbook="$repo_root/ansible/playbooks/fedora.yml"
arch_playbook="$repo_root/ansible/playbooks/arch.yml"
macos_playbook="$repo_root/ansible/playbooks/macos.yml"
profile_preflight="$repo_root/ansible/roles/profile_preflight/tasks/main.yml"
package_installer="$repo_root/ansible/roles/package_installer/tasks/main.yml"
flatpak_feature="$repo_root/ansible/roles/features/flatpak_apps/tasks/main.yml"
flatpak_task="$repo_root/ansible/roles/features/flatpak_apps/tasks/linux.yml"
flatpak_best_effort_task="$repo_root/ansible/roles/features/flatpak_apps/tasks/install_app.yml"
ai_tools_task_main="$repo_root/ansible/roles/features/ai_clis/tasks/main.yml"
ai_tools_unix_task="$repo_root/ansible/roles/features/ai_clis/tasks/unix.yml"
ai_clis_data="$repo_root/home/.chezmoidata/ai-clis.yaml"
packages_data="$repo_root/home/.chezmoidata/packages.yaml"
chezmoi_bootstrap_script="$repo_root/home/.chezmoiscripts/run_once_before_00-bootstrap.sh.tmpl"
workflow_file="$repo_root/.github/workflows/ci.yml"
ansible_config="$repo_root/ansible.cfg"
setup_outcome_task="$repo_root/ansible/roles/setup_outcome/tasks/main.yml"
chezmoi_task_main="$repo_root/ansible/roles/chezmoi/tasks/main.yml"
low_memory_task="$repo_root/ansible/roles/low_memory/tasks/main.yml"

if ! bash -s -- --help < "$repo_root/bootstrap.sh" >/dev/null; then
  echo "expected bootstrap.sh to support README curl execution piped into bash"
  exit 1
fi

search_file() {
  local pattern="$1"
  local path="$2"

  if command -v rg >/dev/null 2>&1; then
    rg -q -- "$pattern" "$path"
  else
    grep -Eq -- "$pattern" "$path"
  fi
}

search_file_literal() {
  local text="$1"
  local path="$2"

  if command -v rg >/dev/null 2>&1; then
    rg -F -q -- "$text" "$path"
  else
    grep -Fq -- "$text" "$path"
  fi
}

if ! search_file "^  vars:$" "$packages_task"; then
  echo "expected Merge package lists task to declare task-local vars"
  exit 1
fi

if ! search_file "^    ci_excluded_system_packages:$" "$packages_task"; then
  echo "expected CI system package exclusion list in task-local vars"
  exit 1
fi

for package in flatpak docker docker.io moby-engine; do
  if ! search_file "^[[:space:]]+- $package$" "$packages_task"; then
    echo "expected $package to be excluded from CI system packages"
    exit 1
  fi
done

if ! search_file "ci_excluded_system_packages if dotfiles_ci" "$packages_task"; then
  echo "expected CI package filtering to contribute ci_excluded_system_packages to the merged exclusions"
  exit 1
fi

if ! search_file "reject\\('in', system_package_exclusions\\)" "$packages_task"; then
  echo "expected package filtering to use the merged system package exclusions list"
  exit 1
fi

if ! search_file "^    docker_desktop_conflicting_system_packages:" "$packages_task"; then
  echo "expected Docker Desktop conflict exclusions in package task vars"
  exit 1
fi

if ! search_file "docker\\.io" "$packages_task"; then
  echo "expected docker.io to be excluded when Docker Desktop is selected on Debian-based Linux"
  exit 1
fi

if ! search_file "'docker_desktop' in \\(features \\| default\\(\\[\\]\\)\\)" "$packages_task"; then
  echo "expected package merge to detect Docker Desktop profile selection"
  exit 1
fi

if ! search_file 'state: latest' "$macos_packages_task"; then
  echo "expected macos.yml to install the latest available Homebrew packages and casks"
  exit 1
fi

if ! search_file 'greedy: true' "$macos_packages_task"; then
  echo "expected macos.yml to upgrade auto-updating Homebrew casks"
  exit 1
fi

if search_file '--no-upgrade' "$windows_bootstrap"; then
  echo "expected bootstrap.ps1 to allow winget to upgrade already-installed packages"
  exit 1
fi

if ! search_file 'Refresh-Repo' "$windows_bootstrap"; then
  echo "expected bootstrap.ps1 to refresh an existing dotfiles checkout"
  exit 1
fi

if ! search_file "not \\(dotfiles_ci \\| default\\(false\\)\\)" "$repo_root/ansible/roles/features/mise/tasks/main.yml"; then
  echo "expected the mise feature role to skip the upstream installer during lightweight CI"
  exit 1
fi

if ! search_file 'Skipping system package refresh in lightweight CI mode\.' "$repo_root/bootstrap.sh"; then
  echo "expected bootstrap.sh to reserve system package refresh skipping for lightweight CI mode"
  exit 1
fi

if ! search_file 'Using checked-out dotfiles repo without refreshing it\.' "$repo_root/bootstrap.sh"; then
  echo "expected bootstrap.sh to preserve the checked-out repo without refreshing it"
  exit 1
fi

if ! search_file 'script_dir' "$repo_root/bootstrap.sh"; then
  echo "expected bootstrap.sh to resolve the checked-out repo"
  exit 1
fi

if ! search_file 'Test-UsingCheckedOutSource' "$windows_bootstrap"; then
  echo "expected bootstrap.ps1 to reuse the checked-out repo source"
  exit 1
fi

if search_file '\(Test-IsAutomation\) -and' "$windows_bootstrap"; then
  echo "expected bootstrap.ps1 to use a local checkout outside automation"
  exit 1
fi

if search_file 'is_automation &&' "$repo_root/bootstrap.sh"; then
  echo "expected bootstrap.sh to use a local checkout outside automation"
  exit 1
fi

if ! search_file 'DOTFILES_REPO' "$repo_root/bootstrap.sh" ||
  ! search_file 'DOTFILES_REPO' "$windows_bootstrap"; then
  echo "expected both bootstrap scripts to support a custom remote repository"
  exit 1
fi

if search_file 'DOTFILES_REPO:-https://' "$repo_root/bootstrap.sh" ||
  search_file '\$repoHttps = "https://' "$windows_bootstrap"; then
  echo "expected downloaded bootstrap scripts to avoid an owner-specific remote fallback"
  exit 1
fi

if ! search_file 'DOTFILES_REPO is required' "$repo_root/bootstrap.sh" ||
  ! search_file 'DOTFILES_REPO is required' "$windows_bootstrap"; then
  echo "expected downloaded bootstrap scripts to explain the required repository URL"
  exit 1
fi

for portable_config in \
  "$repo_root/home/dot_bashrc" \
  "$repo_root/home/dot_config/opencode/opencode.jsonc.tmpl"; do
  if [ ! -f "$portable_config" ]; then
    echo "expected ${portable_config#"$repo_root"/} to exist"
    exit 1
  fi
  if search_file '/home/[^/[:space:]]+' "$portable_config"; then
    echo "expected ${portable_config#"$repo_root"/} to avoid user-specific home paths"
    exit 1
  fi
done

if ! search_file 'Skipping package installs in lightweight CI mode\.' "$windows_bootstrap"; then
  echo "expected bootstrap.ps1 to reserve winget skipping for lightweight CI mode"
  exit 1
fi

if ! search_file 'Skipping chezmoi self-upgrade in lightweight CI mode\.' "$windows_bootstrap"; then
  echo "expected bootstrap.ps1 to reserve chezmoi self-upgrade skipping for lightweight CI mode"
  exit 1
fi

if ! search_file '\$scriptDir' "$windows_bootstrap"; then
  echo "expected bootstrap.ps1 to reuse the checked-out repo during CI"
  exit 1
fi

if ! search_file 'chezmoi apply --source \$chezmoiSource .*--force -v' "$windows_bootstrap"; then
  echo "expected bootstrap.ps1 to run chezmoi apply against the resolved source directory"
  exit 1
fi

if ! search_file 'Assert-LastExitCode "chezmoi apply"' "$windows_bootstrap"; then
  echo "expected bootstrap.ps1 to fail when chezmoi apply returns a non-zero exit code"
  exit 1
fi

if ! search_file 'chezmoi data --source \$chezmoiSource' "$windows_bootstrap"; then
  echo "expected bootstrap.ps1 to read chezmoi data from the resolved source directory"
  exit 1
fi

if ! search_file 'Assert-LastExitCode "winget import"' "$windows_bootstrap"; then
  echo "expected bootstrap.ps1 to fail when winget import returns a non-zero exit code"
  exit 1
fi

if ! search_file 'winget import.*--ignore-versions' "$windows_bootstrap"; then
  echo "expected bootstrap.ps1 to pass --ignore-versions to winget import so packages install at their latest version"
  exit 1
fi

if grep -rnE 'releases/download/v?[0-9]+\.[0-9]+|raw\.githubusercontent\.com/[^/ ]+/[^/ ]+/v?[0-9]+\.[0-9]+' "$repo_root/ansible" "$repo_root/home/.chezmoiscripts" "$repo_root/home/.chezmoidata" "$repo_root/bootstrap.sh" "$repo_root/bootstrap.ps1" "$repo_root/scripts"; then
  echo "expected no hardcoded release versions in download or installer URLs; installers must resolve the latest release at run time"
  exit 1
fi

if grep -rnE 'expected_sha256|sha256sum|shasum' "$repo_root/home/.chezmoiscripts"; then
  echo "expected no checksum-pinned upstream installers; a pinned installer breaks instead of picking up upstream changes"
  exit 1
fi

if grep -nE 'Python\.Python\.3\.[0-9]+' "$packages_data"; then
  echo "expected no minor-versioned Python winget id; name Python.Python.3 and let bootstrap.ps1 resolve the newest minor"
  exit 1
fi

if ! search_file '^[[:space:]]+- Python\.Python\.3$' "$packages_data" ||
  ! search_file_literal 'function Resolve-WingetPackageIds' "$windows_bootstrap" ||
  ! search_file_literal '$pkgs = Resolve-WingetPackageIds -PackageIds $pkgs' "$windows_bootstrap"; then
  echo "expected packages.yaml to list Python.Python.3 and bootstrap.ps1 to resolve it to the newest minor via Resolve-WingetPackageIds"
  exit 1
fi

if ! search_file 'AllowWingetNoApplicableUpgrade' "$windows_bootstrap"; then
  echo "expected bootstrap.ps1 to recognize the winget no-available-upgrade exit path"
  exit 1
fi

if ! search_file '0x8A15002B' "$windows_bootstrap"; then
  echo "expected bootstrap.ps1 to handle winget''s no-available-upgrade exit code"
  exit 1
fi

if search_file '\[uint32\]\$LASTEXITCODE' "$windows_bootstrap"; then
  echo "expected bootstrap.ps1 to compare winget''s signed exit code without a UInt32 cast"
  exit 1
fi

if ! search_file '\-1978335189' "$windows_bootstrap"; then
  echo "expected bootstrap.ps1 to compare winget''s no-available-upgrade exit code as the signed PowerShell LASTEXITCODE value"
  exit 1
fi

if ! search_file 'Assert-LastExitCode "winget install twpayne\.chezmoi" -AllowWingetNoApplicableUpgrade' "$windows_bootstrap"; then
  echo "expected bootstrap.ps1 to tolerate winget''s no-available-upgrade result for chezmoi during idempotency checks"
  exit 1
fi

if ! search_file_literal 'Invoke-BestEffort -Phase "mise" -Name "mise tool lists"' "$windows_bootstrap"; then
  echo "expected bootstrap.ps1 to record mise tool install failures and continue in best-effort mode"
  exit 1
fi

if ! search_file 'Invoke-BestEffort -Phase "ai_cli"' "$windows_bootstrap"; then
  echo "expected bootstrap.ps1 to record AI CLI installer failures and continue in best-effort mode"
  exit 1
fi

if ! search_file '\$setupMode' "$windows_bootstrap" ||
  ! search_file 'DOTFILES_SETUP_MODE' "$windows_bootstrap" ||
  ! search_file 'Write-SetupReport' "$windows_bootstrap"; then
  echo "expected bootstrap.ps1 to support setup modes and print a final failure summary"
  exit 1
fi

if ! search_file '\$script:setupMode -eq "strict"' "$windows_bootstrap"; then
  echo "expected bootstrap.ps1 strict mode to preserve fail-fast installer behavior"
  exit 1
fi

if ! search_file 'docker-ce-cli' "$repo_root/ansible/roles/features/docker_desktop/tasks/linux.yml"; then
  echo "expected Docker Desktop installers to provision docker-ce-cli"
  exit 1
fi

if ! search_file 'download\.docker\.com/linux/ubuntu' "$repo_root/ansible/roles/features/docker_desktop/tasks/linux.yml"; then
  echo "expected Ubuntu Docker Desktop installer to add the official Docker apt repository"
  exit 1
fi

if ! search_file_literal 'dnf -q list --available ghostty' "$repo_root/ansible/roles/features/ghostty_terminal/tasks/linux.yml" ||
  ! search_file_literal 'dnf -q list --available VirtualBox' "$repo_root/ansible/roles/features/virtualbox/tasks/linux.yml"; then
  echo "expected Fedora Ghostty and VirtualBox installers to prefer packages already provided by enabled repos before adding Copr or RPM Fusion"
  exit 1
fi

if ! search_file 'download\.docker\.com/linux/fedora/docker-ce\.repo' "$repo_root/ansible/roles/features/docker_desktop/tasks/linux.yml"; then
  echo "expected Fedora Docker Desktop installer to add the official Docker dnf repository"
  exit 1
fi

if ! search_file '--nogpgcheck' "$repo_root/ansible/roles/features/docker_desktop/tasks/linux.yml"; then
  echo "expected Fedora Docker Desktop installer to allow Docker''s unsigned desktop RPM"
  exit 1
fi

if search_file 'apt_repository:' "$repo_root/ansible/roles/features/docker_desktop/tasks/linux.yml"; then
  echo "expected Ubuntu Docker Desktop installer to avoid the deprecated apt_repository module"
  exit 1
fi

if ! search_file '/etc/apt/sources\.list\.d/docker\.sources' "$repo_root/ansible/roles/features/docker_desktop/tasks/linux.yml"; then
  echo "expected Ubuntu Docker Desktop installer to write Docker deb822 source data"
  exit 1
fi

if ! search_file 'dotfiles_container_ci' "$common_playbook"; then
  echo "expected common flow to derive a CI container fact"
  exit 1
fi

if ! search_file 'GITHUB_ACTIONS' "$common_playbook" || ! search_file "lookup\\('env', 'CI'\\)" "$common_playbook"; then
  echo "expected common flow to detect automation separately from lightweight DOTFILES_CI mode"
  exit 1
fi

if ! search_file 'dotfiles_container_ci' "$flatpak_feature"; then
  echo "expected Flatpak app feature to skip app installs inside CI containers"
  exit 1
fi

if search_file 'ignore_errors: yes' "$flatpak_task"; then
  echo "expected Flatpak app install failures to be avoided or fail clearly, not ignored noisily"
  exit 1
fi

if search_file 'ignore_errors: yes' "$flatpak_best_effort_task" ||
  search_file 'ignore_errors: yes' "$mise_tools_task"; then
  echo "expected Flatpak and mise best-effort installers to record failures without ignore_errors"
  exit 1
fi

if search_file 'ignore_errors: yes' "$ai_tools_unix_task"; then
  echo "expected AI CLI installer failures to fail clearly instead of being ignored noisily"
  exit 1
fi

if search_file 'become:' "$ai_tools_unix_task"; then
  echo "expected AI CLI Unix installers not to use Ansible become"
  exit 1
fi

if search_file 'sudo npm install -g|--prefix /usr/local|/usr/local/lib/node_modules' "$ai_tools_unix_task" ||
  search_file 'sudo npm install -g|--prefix /usr/local|/usr/local/lib/node_modules' "$ai_clis_data"; then
  echo "expected AI CLI npm installers not to target root-owned global npm paths"
  exit 1
fi

if ! search_file 'dotfiles_automation' "$ai_tools_task_main"; then
  echo "expected AI CLI upstream installers to be skipped in automation"
  exit 1
fi

if ! search_file 'Ensure user-local CLI install directories exist' "$ai_tools_task_main" ||
  ! search_file '\.local/bin' "$ai_tools_task_main" ||
  ! search_file '\.local/lib' "$ai_tools_task_main"; then
  echo "expected AI CLI role to create user-local install directories before upstream installers"
  exit 1
fi

if ! search_file 'CODEX_NON_INTERACTIVE' "$ai_tools_unix_task"; then
  echo "expected AI CLI Unix installer task to set non-interactive installer environment in automation"
  exit 1
fi

if ! search_file 'NPM_CONFIG_PREFIX' "$ai_tools_unix_task" ||
  ! search_file "lookup\\('env', 'HOME'\\).*\\.local" "$ai_tools_unix_task"; then
  echo "expected AI CLI Unix installers to use the user-local npm prefix"
  exit 1
fi

if ! search_file "'PATH': lookup\\('env', 'HOME'\\).*\\.local/bin" "$ai_tools_unix_task"; then
  echo "expected AI CLI Unix installers to prefer user-local binaries on PATH"
  exit 1
fi

if ! search_file 'pacman-key --init' "$repo_root/ansible/roles/features/warp_terminal/tasks/linux.yml"; then
  echo "expected Arch Warp installer to initialize the pacman keyring when needed"
  exit 1
fi

if ! search_file 'export DOTFILES_CHEZMOI_DIR="\$chezmoi_dir"' "$repo_root/bootstrap.sh"; then
  echo "expected bootstrap.sh to export DOTFILES_CHEZMOI_DIR for ansible"
  exit 1
fi

if ! search_file '--platform' "$repo_root/bootstrap.sh"; then
  echo "expected bootstrap.sh to accept a CI-only --platform override"
  exit 1
fi

if ! search_file '--best-effort' "$repo_root/bootstrap.sh" ||
  ! search_file '--strict' "$repo_root/bootstrap.sh" ||
  ! search_file 'dotfiles_setup_mode=\$setup_mode' "$repo_root/bootstrap.sh"; then
  echo "expected bootstrap.sh to expose setup mode and pass it to Ansible"
  exit 1
fi

if ! search_file '--platform is only supported when DOTFILES_CI=1\.' "$repo_root/bootstrap.sh"; then
  echo "expected bootstrap.sh to reject platform overrides outside DOTFILES_CI"
  exit 1
fi

if ! search_file_literal 'DISTRO_FAMILY="$(resolve_distro_family)"' "$repo_root/bootstrap.sh" ||
  ! search_file_literal 'platform:f[0-9]*)' "$repo_root/bootstrap.sh"; then
  echo "expected bootstrap.sh to map Fedora rebuilds such as Nobara through os-release ID_LIKE and PLATFORM_ID"
  exit 1
fi

if [ "$(grep -c 'case "\$DISTRO" in' "$repo_root/bootstrap.sh")" -ne 1 ]; then
  echo "expected bootstrap.sh to branch on DISTRO_FAMILY everywhere except resolve_distro_family"
  exit 1
fi

if ! search_file_literal 'nobara-sync cli' "$repo_root/bootstrap.sh"; then
  echo "expected bootstrap.sh to refresh Nobara through its own updater instead of raw dnf upgrade"
  exit 1
fi

if ! search_file 'ansible_playbook="ansible/playbooks/\$platform\.yml"' "$repo_root/bootstrap.sh"; then
  echo "expected bootstrap.sh to select exactly one platform playbook"
  exit 1
fi

if ! search_file 'ansible_args=\(-i "localhost," "\$ansible_playbook"\)' "$repo_root/bootstrap.sh"; then
  echo "expected bootstrap.sh to run only the selected platform playbook"
  exit 1
fi

if ! search_file 'ansible/vars/package_sets/ubuntu\.yml' "$ubuntu_playbook"; then
  echo "expected Ubuntu playbook to load only the Ubuntu package set"
  exit 1
fi

for other_package_set in fedora arch macos; do
  if search_file "ansible/vars/package_sets/${other_package_set}\\.yml" "$ubuntu_playbook"; then
    echo "expected Ubuntu playbook not to load ${other_package_set} package set"
    exit 1
  fi
done

for playbook in "$fedora_playbook" "$arch_playbook" "$macos_playbook"; do
  if ! search_file 'import_tasks: common\.yml' "$playbook"; then
    echo "expected ${playbook##*/} to use the shared platform common flow"
    exit 1
  fi
done

if ! search_file_literal 'dpkg-query -W' "$repo_root/ansible/roles/features/docker_desktop/tasks/linux.yml" ||
  ! search_file_literal 'rpm -q docker-desktop' "$repo_root/ansible/roles/features/docker_desktop/tasks/linux.yml" ||
  ! search_file_literal 'pacman -Q docker-desktop' "$repo_root/ansible/roles/features/docker_desktop/tasks/linux.yml"; then
  echo "expected Docker Desktop install blocks to check for an existing installation first"
  exit 1
fi

if ! search_file_literal 'desktop.docker.com/linux/main/amd64/appcast.xml' "$repo_root/ansible/roles/features/docker_desktop/tasks/linux.yml" ||
  ! search_file_literal 'sparkle:shortVersionString' "$repo_root/ansible/roles/features/docker_desktop/tasks/linux.yml"; then
  echo "expected Docker Desktop tasks to resolve the latest release from Docker's Linux appcast"
  exit 1
fi

if [ "$(grep -c 'dotfiles_docker_desktop_install_needed | default(false) | bool' "$repo_root/ansible/roles/features/docker_desktop/tasks/linux.yml")" -ne 6 ]; then
  echo "expected all three Docker Desktop install blocks to be gated on the version comparison"
  exit 1
fi

if grep -rnE "regex_(search|replace|findall)\([\"'][^\"']*\\\\\\\\" "$repo_root/ansible" --include='*.yml'; then
  echo "expected Ansible regex filters to use single backslashes; doubled backslashes never match inside folded scalars"
  exit 1
fi

if ! search_file_literal 'download.virtualbox.org/virtualbox/LATEST.TXT' "$repo_root/ansible/roles/features/virtualbox/tasks/linux.yml" ||
  ! search_file_literal 'apt-get install -y "$vbox_package"' "$repo_root/ansible/roles/features/virtualbox/tasks/linux.yml" ||
  ! search_file_literal 'apt-cache search --names-only' "$repo_root/ansible/roles/features/virtualbox/tasks/linux.yml" ||
  ! search_file_literal 'leaving the installed ${oracle_installed} alone' "$repo_root/ansible/roles/features/virtualbox/tasks/linux.yml" ||
  ! search_file_literal 'keeping the installed ${oracle_installed}' "$repo_root/ansible/roles/features/virtualbox/tasks/linux.yml" ||
  ! search_file_literal 'keyring_tmp="$(mktemp)"' "$repo_root/ansible/roles/features/virtualbox/tasks/linux.yml" ||
  ! search_file_literal 'apt-get install -y virtualbox virtualbox-dkms virtualbox-qt' "$repo_root/ansible/roles/features/virtualbox/tasks/linux.yml"; then
  echo "expected the Debian VirtualBox task to use Oracle's repository with the release line resolved at run time, falling back to the archive package"
  exit 1
fi

if search_file 'virtualbox-[0-9]+\.[0-9]+' "$repo_root/ansible/roles/features/virtualbox/tasks/linux.yml"; then
  echo "expected no hardcoded VirtualBox release line in the Debian VirtualBox task"
  exit 1
fi

if ! search_file_literal '/opt/homebrew/bin/bash' "$repo_root/ansible/roles/features/shell/tasks/macos.yml" ||
  ! search_file_literal 'shell_macos_login_shell' "$repo_root/ansible/roles/features/shell/tasks/macos.yml" ||
  ! search_file_literal 'path: /etc/shells' "$repo_root/ansible/roles/features/shell/tasks/macos.yml" ||
  search_file 'ignore_errors' "$repo_root/ansible/roles/features/shell/tasks/macos.yml" ||
  [ -e "$repo_root/home/.chezmoiscripts/run_once_after_macos-install-bash.sh.tmpl" ]; then
  echo "expected the macOS shell role to own the Homebrew bash login shell, without ignore_errors and without the duplicate run_once chsh script"
  exit 1
fi

if ! search_file_literal 'ensure_sudo_access() {' "$repo_root/bootstrap.sh" ||
  search_file_literal 'ensure_linux_sudo_access' "$repo_root/bootstrap.sh" ||
  ! search_file_literal 'skip_macos_sudo "$USER is not an administrator' "$repo_root/bootstrap.sh" ||
  ! search_file_literal 'DOTFILES_SUDO_PASSWORD_FILE:-' "$repo_root/bootstrap.sh" ||
  ! search_file_literal 'if [ -n "$become_password_file" ]; then' "$repo_root/bootstrap.sh" ||
  search_file_literal 'if [ "$OS" = "Linux" ] && [ -n "$become_password_file" ]' "$repo_root/bootstrap.sh"; then
  echo "expected bootstrap.sh to collect the sudo password and pass --become-password-file on macOS as well as Linux"
  exit 1
fi

if ! search_file_literal 'plan_step run "Upgrade Ansible" upgrade_ansible' "$repo_root/bootstrap.sh" ||
  search_file '^      - ansible$' "$repo_root/ansible/vars/package_sets/macos.yml"; then
  echo "expected bootstrap.sh to upgrade Ansible on macOS before the playbook, and not via the brew package set"
  exit 1
fi

for gone in \
  "$repo_root/home/.chezmoiscripts/run_once_install_llmfit.ps1.tmpl" \
  "$repo_root/home/.chezmoiscripts/run_once_install_zoxide.sh.tmpl" \
  "$repo_root/home/.chezmoiscripts/run_once_install_superfile.sh.tmpl" \
  "$repo_root/home/.chezmoiscripts/run_once_install_superfile.ps1.tmpl" \
  "$repo_root/home/.chezmoidata/devtools.yaml" \
  "$repo_root/ansible/roles/features/core_cli" \
  "$repo_root/ansible/roles/features/starship_prompt" \
  "$repo_root/ansible/roles/features/npm_global_tools" \
  "$repo_root/ansible/roles/features/bitwarden_cli" \
  "$repo_root/ansible/roles/features/llmfit"; do
  if [ -e "$gone" ]; then
    echo "expected ${gone#"$repo_root"/} to be gone; those tools are installed from the mise tool lists in home/dot_config/mise/conf.d/"
    exit 1
  fi
done

if ! search_file_literal 'function Install-Mise' "$windows_bootstrap" ||
  ! search_file_literal 'winget install --id jdx.mise' "$windows_bootstrap" ||
  ! search_file_literal 'Add-UserPathEntry -Directory (Join-Path $env:LOCALAPPDATA "mise\shims")' "$windows_bootstrap" ||
  ! search_file_literal 'RegistryValueKind]::ExpandString' "$windows_bootstrap" ||
  ! search_file_literal '$env:MISE_YES = "1"' "$windows_bootstrap" ||
  ! search_file_literal 'mise install' "$windows_bootstrap" ||
  ! search_file_literal 'mise upgrade' "$windows_bootstrap" ||
  ! search_file_literal 'mise ls --missing' "$windows_bootstrap" ||
  ! search_file_literal 'Invoke-BestEffort -Phase "mise" -Name "mise"' "$windows_bootstrap"; then
  echo "expected bootstrap.ps1 to install mise with winget, put its shims on the user PATH, and install and upgrade the mise tool lists non-interactively"
  exit 1
fi

if [ "$(grep -n 'Invoke-BestEffort -Phase "windows_packages"' "$windows_bootstrap" | cut -d: -f1)" -gt "$(grep -n 'Invoke-BestEffort -Phase "mise" -Name "mise tool lists"' "$windows_bootstrap" | cut -d: -f1)" ]; then
  echo "expected bootstrap.ps1 to install the mise tool lists after the winget import, so npm: entries find node on PATH"
  exit 1
fi

if ! search_file_literal 'Start-Progress -Total 8' "$windows_bootstrap" ||
  [ "$(grep -c '^Complete-ProgressStep$' "$windows_bootstrap")" -ne 8 ]; then
  echo "expected the Windows progress bar total to match the number of Complete-ProgressStep calls"
  exit 1
fi

if ! search_file_literal 'required_ansible_collections_present' "$repo_root/bootstrap.sh" ||
  ! search_file_literal 'Continuing with the already-installed versions' "$repo_root/bootstrap.sh"; then
  echo "expected bootstrap.sh to fall back to installed Ansible collections when Galaxy is unreachable"
  exit 1
fi

if ! search_file_literal 'force-remove-reinstreq docker-desktop' "$repo_root/bootstrap.sh" ||
  ! search_file_literal "repair_broken_docker_desktop" "$repo_root/bootstrap.sh"; then
  echo "expected bootstrap.sh to remove a half-installed Docker Desktop before running apt"
  exit 1
fi

docker_desktop_tasks="$repo_root/ansible/roles/features/docker_desktop/tasks/linux.yml"
if ! search_file_literal 'https://download.docker.com/linux/ubuntu/dists/' "$common_playbook" ||
  ! search_file_literal 'dotfiles_docker_desktop_ubuntu_codenames:' "$common_playbook" ||
  ! search_file_literal 'dotfiles_docker_desktop_ubuntu_codenames' "$profile_preflight" ||
  ! search_file_literal 'dotfiles_docker_desktop_ubuntu_codenames' "$docker_desktop_tasks"; then
  echo "expected the Docker Desktop Ubuntu codename list to be read from download.docker.com at run time and shared via dotfiles_docker_desktop_ubuntu_codenames"
  exit 1
fi
if grep -qE -- "- (focal|jammy|noble|oracular|plucky|questing|resolute)$" "$common_playbook" ||
  search_file_literal "'focal'" "$profile_preflight" ||
  search_file_literal "'focal'" "$docker_desktop_tasks"; then
  echo "expected no hardcoded Ubuntu codename whitelist for Docker Desktop"
  exit 1
fi
if ! search_file_literal 'checksums.txt' "$docker_desktop_tasks" ||
  ! search_file_literal 'checksum: "sha256:{{ dotfiles_docker_desktop_package_sha256 }}"' "$docker_desktop_tasks" ||
  ! search_file_literal 'Fail when the Docker Desktop package cannot be verified' "$docker_desktop_tasks"; then
  echo "expected the Docker Desktop package to be verified against Docker's published checksums.txt before install"
  exit 1
fi

referenced_platform_keys="$(grep -rhoE 'dotfiles_platform\.[a-z_]+' "$repo_root/ansible" --include='*.yml' | sed 's/^dotfiles_platform\.//' | sort -u)"
for playbook in "$ubuntu_playbook" "$fedora_playbook" "$arch_playbook" "$macos_playbook"; do
  for key in $referenced_platform_keys; do
    if ! search_file "^ {6}${key}:" "$playbook"; then
      echo "expected ${playbook##*/} to define dotfiles_platform.${key} (referenced under ansible/)"
      exit 1
    fi
  done
done

if ! search_file 'supported_platforms' "$repo_root/ansible/vars/profiles/personal.yml" ||
  ! search_file 'features:' "$repo_root/ansible/vars/profiles/personal.yml" ||
  ! search_file 'supported_platforms' "$repo_root/ansible/vars/profiles/work.yml" ||
  ! search_file 'features:' "$repo_root/ansible/vars/profiles/work.yml"; then
  echo "expected personal and work profiles to declare supported_platforms and features"
  exit 1
fi

if ! search_file 'Unknown feature\(s\)' "$profile_preflight"; then
  echo "expected profile preflight to fail clearly for unknown features"
  exit 1
fi

if ! search_file 'does not support platform' "$profile_preflight"; then
  echo "expected profile preflight to fail clearly for unsupported profile/platform combinations"
  exit 1
fi

if ! search_file 'platform_package_data\.package_sets' "$package_installer"; then
  echo "expected package installer to use the selected platform package set"
  exit 1
fi

if ! search_file 'dotfiles_chezmoi_setup_data' "$repo_root/ansible/roles/chezmoi/tasks/main.yml"; then
  echo "expected chezmoi apply to receive feature-aware setup data"
  exit 1
fi

if ! search_file 'dotfiles_setup_mode' "$common_playbook" ||
  ! search_file 'DOTFILES_SETUP_MODE' "$common_playbook" ||
  ! search_file 'Show setup outcome summary' "$common_playbook" ||
  ! search_file 'dotfiles_setup_failures' "$common_playbook"; then
  echo "expected common flow to support setup modes and print a final outcome summary"
  exit 1
fi

if ! awk '
  /^- name: Execute setup tasks$/ { in_block = 1; next }
  /^- name:/ { in_block = 0 }
  in_block && /name: profile_preflight/ { found = 1 }
  END { exit(found ? 0 : 1) }
' "$common_playbook"; then
  echo "expected profile preflight to run inside the reported setup block"
  exit 1
fi

if ! search_file '^remote_tmp = /tmp/ansible-\$\{USER\}/tmp$' "$ansible_config"; then
  echo "expected Ansible remote temp files to use /tmp so a full HOME does not block the final summary"
  exit 1
fi

if ! search_file 'DOTFILES_LOW_MEMORY' "$common_playbook" ||
  ! search_file 'DOTFILES_LOW_MEMORY_THRESHOLD_MB' "$common_playbook" ||
  ! search_file 'dotfiles_low_memory_setup' "$common_playbook" ||
  ! search_file 'role: low_memory' "$execution_playbook"; then
  echo "expected common flow to detect low-memory machines and run the low-memory role"
  exit 1
fi

if ! search_file 'DOTFILES_SWAPFILE_SIZE_MB' "$low_memory_task" ||
  ! search_file 'DOTFILES_MIN_SWAP_MB' "$low_memory_task" ||
  ! search_file 'fallocate -l' "$low_memory_task" ||
  ! search_file 'mkswap /swapfile' "$low_memory_task" ||
  ! search_file 'swapon /swapfile' "$low_memory_task"; then
  echo "expected low-memory role to prepare a configurable Linux swapfile"
  exit 1
fi

if ! search_file 'NODE_OPTIONS' "$ai_tools_unix_task" ||
  ! search_file 'NPM_CONFIG_JOBS' "$ai_tools_unix_task" ||
  ! search_file "'MISE_JOBS': '1'" "$mise_tools_task" ||
  ! search_file 'dotfiles_low_memory_setup' "$mise_tools_task"; then
  echo "expected the AI CLI installer and mise to do less work in parallel in low-memory mode"
  exit 1
fi

if ! search_file_literal '# Dotfiles setup report' "$setup_outcome_task" ||
  ! search_file_literal '## Errors' "$setup_outcome_task" ||
  ! search_file_literal '## Not detected after setup' "$setup_outcome_task" ||
  ! search_file_literal '## Skipped intentionally' "$setup_outcome_task" ||
  ! search_file_literal '## Installed or present after setup' "$setup_outcome_task" ||
  ! search_file_literal '## Completed steps' "$setup_outcome_task" ||
  ! search_file_literal '- Result:' "$setup_outcome_task"; then
  echo "expected setup outcome role to write a Markdown report with result, error, missing, skipped, installed, and completed sections"
  exit 1
fi

if ! search_file_literal 'DOTFILES_BOOTSTRAP_OUTCOMES_FILE' "$setup_outcome_task" ||
  ! search_file_literal "map('from_json')" "$setup_outcome_task" ||
  ! search_file_literal "'phase': 'bootstrap'" "$setup_outcome_task"; then
  echo "expected setup outcome role to merge bootstrap step outcomes into the report"
  exit 1
fi

if search_file_literal 'json_query' "$setup_outcome_task"; then
  echo "expected setup outcome role not to depend on the optional jmespath library"
  exit 1
fi

for verifier in dpkg-query rpm pacman brew flatpak 'mise' 'command -v'; do
  if ! search_file "$verifier" "$setup_outcome_task"; then
    echo "expected setup outcome role to verify selected package/app entries with $verifier"
    exit 1
  fi
done

if ! search_file 'dotfiles_package_plan' "$package_installer" ||
  ! search_file 'excluded_system_packages' "$package_installer" ||
  ! search_file 'dotfiles_setup_configured' "$common_playbook" ||
  ! search_file 'dotfiles_setup_skipped' "$setup_outcome_task"; then
  echo "expected setup outcome data to include package plans, configured phases, and skipped entries"
  exit 1
fi

if ! search_file 'export PATH="\$HOME/\.local/bin:\$PATH"' "$repo_root/test/ci_idempotency_check.sh"; then
  echo "expected CI idempotency checks to find tools installed into HOME/.local/bin by bootstrap.sh"
  exit 1
fi

if ! search_file '--source' "$repo_root/ansible/roles/chezmoi/tasks/main.yml"; then
  echo "expected chezmoi ansible role to pass the resolved source directory explicitly"
  exit 1
fi

chezmoi_best_effort_task="$repo_root/ansible/roles/chezmoi/tasks/apply_best_effort.yml"
if ! search_file_literal 'Run chezmoi apply (strict)' "$chezmoi_task_main" ||
  ! search_file_literal 'apply_best_effort.yml' "$chezmoi_task_main" ||
  ! search_file_literal "'--exclude=scripts'" "$chezmoi_best_effort_task" ||
  ! search_file_literal "'--include=scripts', item.target" "$chezmoi_best_effort_task" ||
  ! search_file_literal '--path-style=source-absolute' "$chezmoi_best_effort_task" ||
  ! search_file_literal 'name: record_failure' "$chezmoi_best_effort_task" ||
  ! search_file_literal "'before'" "$chezmoi_best_effort_task" ||
  ! search_file_literal "'after'" "$chezmoi_best_effort_task"; then
  echo "expected best-effort chezmoi apply to isolate files and each run_ script and record per-script failures"
  exit 1
fi

if search_file_literal 'ignore_errors' "$chezmoi_best_effort_task"; then
  echo "expected best-effort chezmoi apply to record failures without ignore_errors"
  exit 1
fi

if ! awk '
  /^install_chezmoi_release_binary\(\) \{/ { in_fn = 1 }
  in_fn && /"\$tmp_binary" --version/ { verified = 1 }
  in_fn && /mv "\$tmp_binary" "\$HOME\/.local\/bin\/chezmoi"/ { if (!verified) bad = 1 }
  in_fn && /^}/ { in_fn = 0 }
  END { exit(bad ? 1 : 0) }
' "$repo_root/bootstrap.sh"; then
  echo "expected bootstrap.sh to verify the downloaded chezmoi binary before installing it"
  exit 1
fi

for needle in \
  'run_step() {' \
  'plan_step critical "Install chezmoi" install_chezmoi' \
  'plan_step critical "Install Ansible" install_ansible' \
  'plan_step run "Refresh Ansible collections from Galaxy" refresh_ansible_collections' \
  'plan_step critical "Required Ansible collections" verify_ansible_collections' \
  'plan_step run "System package refresh" update_system' \
  'run_step "${planned_step_name[$step_index]}" "${planned_step_action[$step_index]}"' \
  'run_step --critical "${planned_step_name[$step_index]}" "${planned_step_action[$step_index]}"' \
  'trap on_exit EXIT' \
  'write_fallback_report' \
  'write_bootstrap_outcomes_file' \
  'export DOTFILES_BOOTSTRAP_OUTCOMES_FILE="$bootstrap_outcomes_file"' \
  'report_written_by_ansible' \
  '# Dotfiles setup report'; do
  if ! search_file_literal "$needle" "$repo_root/bootstrap.sh"; then
    echo "expected bootstrap.sh to run prerequisite steps through run_step and always write a setup report (missing: $needle)"
    exit 1
  fi
done

if ! search_file_literal 'curl_is_snap' "$repo_root/bootstrap.sh" ||
  ! search_file_literal '/snap/*|/var/lib/snapd/*' "$repo_root/bootstrap.sh" ||
  ! search_file_literal 'https://github.com/twpayne/chezmoi/releases/latest/download/' "$repo_root/bootstrap.sh" ||
  ! search_file_literal 'asset="chezmoi-${os}-${arch}"' "$repo_root/bootstrap.sh" ||
  ! search_file_literal 'install_chezmoi_from_package_manager' "$repo_root/bootstrap.sh"; then
  echo "expected bootstrap.sh to replace Snap curl with the native package and to fall back when the chezmoi installer fails"
  exit 1
fi

if ! search_file_literal 'DEBIAN_FRONTEND=noninteractive' "$repo_root/bootstrap.sh"; then
  echo "expected bootstrap.sh apt operations to be non-interactive"
  exit 1
fi

if ! search_file_literal '} finally {' "$windows_bootstrap" ||
  ! search_file_literal 'Invoke-BestEffort -Phase "chezmoi" -Name "chezmoi apply"' "$windows_bootstrap" ||
  ! search_file_literal 'Add-SetupFailure -Phase "aborted"' "$windows_bootstrap" ||
  ! search_file_literal '# Dotfiles setup report' "$windows_bootstrap"; then
  echo "expected bootstrap.ps1 to always write the setup report and to treat chezmoi apply as a best-effort step"
  exit 1
fi

if ! search_file_literal '{{- if ne .chezmoi.os "windows" -}}' "$chezmoi_bootstrap_script"; then
  echo "expected chezmoi bootstrap script to skip Bash execution on Windows and trim the newline before the Unix shebang"
  exit 1
fi

if ! awk 'NR == 2 { exit($0 == "#!/usr/bin/env bash" ? 0 : 1) }' "$chezmoi_bootstrap_script"; then
  echo "expected chezmoi bootstrap script template to place the shebang immediately after the opening conditional"
  exit 1
fi

if awk '
  /^  set_fact:/ { in_set_fact = 1; next }
  /^  [A-Za-z_]/ { in_set_fact = 0 }
  in_set_fact && /ci_excluded_system_packages:/ { found = 1 }
  END { exit(found ? 0 : 1) }
' "$packages_task"; then
  echo "ci_excluded_system_packages must not be declared inside set_fact"
  exit 1
fi

if ! search_file 'https://mise\.run' "$mise_feature_task" ||
  ! search_file 'https://mise\.jdx\.dev/VERSION' "$mise_feature_task" ||
  ! search_file 'DOTFILES_CHANGED' "$mise_feature_task" ||
  search_file 'self-update' "$mise_feature_task" ||
  search_file 'MISE_VERSION' "$mise_feature_task"; then
  echo "expected the mise feature role to run the unpinned mise.run installer only when mise is absent or behind https://mise.jdx.dev/VERSION (not mise self-update, which needs the rate-limited GitHub API) and report changed from a fingerprint"
  exit 1
fi

if ! search_file 'mise ls --missing|- --missing' "$mise_tools_task" ||
  ! search_file '- outdated' "$mise_tools_task" ||
  ! search_file "'MISE_YES': '1'" "$mise_tools_task" ||
  ! search_file 'GITHUB_TOKEN' "$mise_tools_task" ||
  ! search_file 'dotfiles_mise_missing_tools_before \| length > 0' "$mise_tools_task" ||
  ! search_file 'dotfiles_mise_outdated_tools_before \| length > 0' "$mise_tools_task" ||
  ! search_file 'failure_phase: mise' "$mise_tools_task" ||
  ! search_file 'Record each mise tool still missing after install' "$mise_tools_task"; then
  echo "expected mise_tools to capture the missing and outdated tools before acting, derive changed from them, and record every tool still missing"
  exit 1
fi

if awk '
  /^- name: (Install missing|Upgrade) mise tools/ { in_task = 1; next }
  /^- name:/ { in_task = 0 }
  in_task && /changed_when: false/ { found = 1 }
  END { exit(found ? 0 : 1) }
' "$mise_tools_task"; then
  echo "expected mise install and upgrade tasks to report changed from the captured tool state, never changed_when: false"
  exit 1
fi

if [ "$(grep -n 'name: Apply Chezmoi$' "$execution_playbook" | cut -d: -f1)" -gt "$(grep -n 'name: Install mise tool lists$' "$execution_playbook" | cut -d: -f1)" ] ||
  [ "$(grep -n 'name: Install mise tool lists$' "$execution_playbook" | cut -d: -f1)" -gt "$(grep -n 'name: Enable selected services$' "$execution_playbook" | cut -d: -f1)" ]; then
  echo "expected the mise_tools phase to run after chezmoi apply (which writes the conf.d lists) and before the services phase"
  exit 1
fi

if ! search_file '"mise_tools : "' "$repo_root/bootstrap.sh"; then
  echo "expected the bootstrap.sh progress bar to track the mise_tools phase"
  exit 1
fi

if ! search_file 'dotfiles_known_mise_tool_lists' "$profile_preflight" ||
  ! search_file 'home/dot_config/mise/conf.d' "$profile_preflight"; then
  echo "expected preflight to accept a mise tool list in home/dot_config/mise/conf.d as a feature implementation"
  exit 1
fi

if ! awk '/dotfiles_feature_execution_order:/ { getline; exit($0 ~ /^      - mise$/ ? 0 : 1) }' "$profile_preflight"; then
  echo "expected mise to be the first feature role in dotfiles_feature_execution_order"
  exit 1
fi

if search_file 'DOTFILES_CI:' "$workflow_file"; then
  echo "expected ci.yml to run the full install path by default"
  exit 1
fi

if ! search_file 'GITHUB_TOKEN:' "$workflow_file"; then
  echo "expected ci.yml to expose GITHUB_TOKEN for installer metadata lookups"
  exit 1
fi

if ! search_file 'set-safe-directory: false' "$workflow_file"; then
  echo "expected Windows checkout to avoid global safe.directory writes in the runner temp HOME"
  exit 1
fi

if ! search_file 'profile: \[personal, work\]' "$workflow_file"; then
  echo "expected ci.yml to exercise both personal and work profiles"
  exit 1
fi

if ! search_file './bootstrap\.sh --profile \$\{\{ matrix\.profile \}\}' "$workflow_file"; then
  echo "expected ci.yml to pass matrix.profile through bootstrap.sh"
  exit 1
fi

if ! search_file '\.\\bootstrap\.ps1 -ProfileName \$\{\{ matrix\.profile \}\}' "$workflow_file"; then
  echo "expected ci.yml to pass matrix.profile through bootstrap.ps1"
  exit 1
fi

if ! search_file '\./bootstrap\.sh --profile \$\{\{ matrix\.profile \}\} --strict' "$workflow_file"; then
  echo "expected ci.yml to run bootstrap.sh in strict mode so a failed install fails the job"
  exit 1
fi

if ! search_file '-SetupMode strict' "$workflow_file"; then
  echo "expected ci.yml to run bootstrap.ps1 in strict mode so a failed install fails the job"
  exit 1
fi

if ! search_file 'test/ci_setup_report_check\.sh' "$workflow_file"; then
  echo "expected ci.yml to verify the setup report says the run completed successfully"
  exit 1
fi

if ! search_file 'Result: Completed successfully\.' "$workflow_file"; then
  echo "expected the Windows CI job to verify the setup report says the run completed successfully"
  exit 1
fi

if ! search_file 'test/test_harness\.sh' "$workflow_file"; then
  echo "expected ci.yml to run the test harness"
  exit 1
fi

if ! search_file 'Check Idempotency' "$workflow_file"; then
  echo "expected ci.yml to include idempotency checks"
  exit 1
fi

if ! search_file 'chezmoi diff --source "\$PWD"' "$workflow_file"; then
  echo "expected ci.yml to verify managed-file idempotency with chezmoi diff"
  exit 1
fi

if ! search_file 'output_log="\$\(mktemp\)"' "$repo_root/test/ci_idempotency_check.sh"; then
  echo "expected ci.yml to write idempotency logs outside the repo source tree"
  exit 1
fi

if ! search_file 'chezmoi_diff="\$\(mktemp\)"' "$repo_root/test/ci_idempotency_check.sh"; then
  echo "expected ci.yml to write chezmoi diff output outside the repo source tree"
  exit 1
fi

# Desktop settings follow the detected desktop environment, never the distro.
gnome_role_main="$repo_root/ansible/roles/gnome/tasks/main.yml"
kde_role_main="$repo_root/ansible/roles/kde/tasks/main.yml"
desktop_base_feature="$repo_root/ansible/roles/features/desktop_base/tasks/main.yml"
chezmoi_setup_data_task="$repo_root/ansible/roles/chezmoi_setup_data/tasks/main.yml"
bootstrap_script="$repo_root/bootstrap.sh"

if ! search_file_literal "scripts/detect-desktop.sh" "$common_playbook"; then
  echo "expected common.yml to detect the desktop environment with scripts/detect-desktop.sh"
  exit 1
fi

if ! search_file_literal "scripts/detect-desktop.sh" "$bootstrap_script"; then
  echo "expected bootstrap.sh to run the same desktop detector as the playbooks"
  exit 1
fi

if search_file_literal 'export DOTFILES_DESKTOP="$desktop"' "$bootstrap_script"; then
  echo "expected bootstrap.sh not to export its detected desktop: the playbook runs the same detector, and an exported value would replace the report's evidence with DOTFILES_DESKTOP=..."
  exit 1
fi

if ! search_file "gnome\|kde\|none\|other\)" "$repo_root/scripts/detect-desktop.sh"; then
  echo "expected detect-desktop.sh to accept every value it can print back through DOTFILES_DESKTOP"
  exit 1
fi

if ! search_file "dotfiles_desktop \| default\('none'\) == 'gnome'" "$gnome_role_main"; then
  echo "expected the gnome role to run only when the detected desktop is GNOME"
  exit 1
fi

if search_file "distro_key == 'fedora'" "$gnome_role_main"; then
  echo "expected the gnome role to stop gating on the distro"
  exit 1
fi

if ! search_file "dotfiles_desktop \| default\('none'\) == 'kde'" "$kde_role_main"; then
  echo "expected the kde role to run only when the detected desktop is KDE Plasma"
  exit 1
fi

for role in gnome kde; do
  if ! search_file "name: $role$" "$desktop_base_feature"; then
    echo "expected desktop_base to dispatch to the $role role"
    exit 1
  fi
done

if ! search_file_literal "dotfiles_desktop | default('none') not in ['gnome', 'kde']" "$desktop_base_feature"; then
  echo "expected desktop_base to record skipped desktop settings when no supported desktop is detected"
  exit 1
fi

if ! search_file_literal "dotfiles_desktop:" "$chezmoi_setup_data_task"; then
  echo "expected chezmoi setup data to expose dotfiles_desktop to templates"
  exit 1
fi

if ! search_file_literal "kde-settings-sync.sh" "$repo_root/ansible/roles/kde/tasks/linux.yml"; then
  echo "expected the kde role to restore settings through scripts/kde-settings-sync.sh"
  exit 1
fi

echo "CI bootstrap regressions passed"
