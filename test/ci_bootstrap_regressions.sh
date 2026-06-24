#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
packages_task="$repo_root/ansible/roles/packages/tasks/main.yml"
debian_packages_task="$repo_root/ansible/roles/packages/tasks/linux-debian.yml"
fedora_packages_task="$repo_root/ansible/roles/packages/tasks/linux-fedora.yml"
arch_packages_task="$repo_root/ansible/roles/packages/tasks/linux-arch.yml"
macos_packages_task="$repo_root/ansible/roles/packages/tasks/macos.yml"
lazygit_task="$repo_root/ansible/roles/git_tools/tasks/linux-lazygit.yml"
windows_bootstrap="$repo_root/bootstrap.ps1"
docker_task_main="$repo_root/ansible/roles/docker/tasks/main.yml"
git_tools_task_main="$repo_root/ansible/roles/git_tools/tasks/main.yml"
services_task_main="$repo_root/ansible/roles/services/tasks/main.yml"
setup_playbook="$repo_root/ansible/playbooks/setup.yml"
common_playbook="$repo_root/ansible/playbooks/common.yml"
ubuntu_playbook="$repo_root/ansible/playbooks/ubuntu.yml"
fedora_playbook="$repo_root/ansible/playbooks/fedora.yml"
arch_playbook="$repo_root/ansible/playbooks/arch.yml"
macos_playbook="$repo_root/ansible/playbooks/macos.yml"
profile_preflight="$repo_root/ansible/roles/profile_preflight/tasks/main.yml"
package_installer="$repo_root/ansible/roles/package_installer/tasks/main.yml"
flatpak_feature="$repo_root/ansible/roles/features/flatpak_apps/tasks/main.yml"
flatpak_task="$repo_root/ansible/roles/flatpak/tasks/linux.yml"
flatpak_best_effort_task="$repo_root/ansible/roles/flatpak/tasks/install_app_best_effort.yml"
ai_tools_task_main="$repo_root/ansible/roles/ai_tools/tasks/main.yml"
ai_tools_unix_task="$repo_root/ansible/roles/ai_tools/tasks/unix.yml"
ai_tools_unix_best_effort_task="$repo_root/ansible/roles/ai_tools/tasks/install_unix_cli_best_effort.yml"
devtools_task_main="$repo_root/ansible/roles/devtools/tasks/main.yml"
devtools_npm_best_effort_task="$repo_root/ansible/roles/devtools/tasks/install_npm_global_best_effort.yml"
ai_clis_data="$repo_root/.chezmoidata/ai-clis.yaml"
chezmoi_bootstrap_script="$repo_root/.chezmoiscripts/run_once_before_00-bootstrap.sh.tmpl"
workflow_file="$repo_root/.github/workflows/ci.yml"
ansible_config="$repo_root/ansible.cfg"
run_feature_task="$repo_root/ansible/playbooks/run_feature_best_effort.yml"
setup_outcome_task="$repo_root/ansible/roles/setup_outcome/tasks/main.yml"
low_memory_task="$repo_root/ansible/roles/low_memory/tasks/main.yml"
linux_privileged_task_files=(
  "$debian_packages_task"
  "$fedora_packages_task"
  "$arch_packages_task"
  "$low_memory_task"
  "$repo_root/ansible/roles/shell/tasks/linux.yml"
  "$repo_root/ansible/roles/docker/tasks/linux.yml"
  "$repo_root/ansible/roles/linux_apps/tasks/linux-warp.yml"
  "$repo_root/ansible/roles/linux_apps/tasks/linux-virtualbox.yml"
  "$repo_root/ansible/roles/linux_apps/tasks/linux-kiro.yml"
  "$repo_root/ansible/roles/linux_apps/tasks/linux-ghostty.yml"
  "$repo_root/ansible/roles/linux_apps/tasks/linux-docker-desktop.yml"
)

if ! bash -c "$(cat "$repo_root/bootstrap.sh")" -- --help >/dev/null; then
  echo "expected bootstrap.sh to support README curl execution with bash -c"
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

for linux_task in "${linux_privileged_task_files[@]}"; do
  if search_file 'become:' "$linux_task"; then
    echo "expected ${linux_task#$repo_root/} to avoid Ansible become for Linux localhost setup"
    exit 1
  fi
done

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

if ! search_file "'docker-desktop' in \\(linux_native_apps \\| default\\(\\[\\]\\)\\)" "$packages_task"; then
  echo "expected package merge to detect Docker Desktop profile selection"
  exit 1
fi

for distro_task in "$debian_packages_task" "$fedora_packages_task" "$arch_packages_task"; do
  if search_file 'become:' "$distro_task"; then
    echo "expected ${distro_task##*/} to avoid Ansible become for Linux localhost package installs"
    exit 1
  fi

  if ! search_file 'sudo -S -p' "$distro_task" || ! search_file 'dotfiles_sudo_password_file' "$distro_task"; then
    echo "expected ${distro_task##*/} to feed sudo from DOTFILES_SUDO_PASSWORD_FILE"
    exit 1
  fi
done

if ! search_file 'apt-get install -y' "$debian_packages_task"; then
  echo "expected Debian package task to install packages with apt-get"
  exit 1
fi

if ! search_file 'dnf install -y' "$fedora_packages_task"; then
  echo "expected Fedora package task to install packages with dnf"
  exit 1
fi

if ! search_file 'pacman -S --noconfirm --needed' "$arch_packages_task"; then
  echo "expected Arch package task to install packages with pacman"
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

if ! search_file "not \\(dotfiles_ci \\| default\\(false\\)\\)" "$docker_task_main"; then
  echo "expected docker role to skip service management during CI"
  exit 1
fi

if ! search_file "not \\(dotfiles_ci \\| default\\(false\\)\\)" "$git_tools_task_main"; then
  echo "expected lazygit role to skip upstream installs during CI"
  exit 1
fi

if ! search_file 'Skipping system package refresh in lightweight CI mode\.' "$repo_root/bootstrap.sh"; then
  echo "expected bootstrap.sh to reserve system package refresh skipping for lightweight CI mode"
  exit 1
fi

if ! search_file 'Using checked-out dotfiles repo without refreshing it\.' "$repo_root/bootstrap.sh"; then
  echo "expected bootstrap.sh to preserve the checked-out repo without refreshing it in automation"
  exit 1
fi

if ! search_file 'script_dir' "$repo_root/bootstrap.sh"; then
  echo "expected bootstrap.sh to resolve the checked-out repo during CI"
  exit 1
fi

if ! search_file 'Test-IsAutomation' "$windows_bootstrap"; then
  echo "expected bootstrap.ps1 to distinguish automation from lightweight CI mode"
  exit 1
fi

if ! search_file 'Test-UsingCheckedOutSource' "$windows_bootstrap"; then
  echo "expected bootstrap.ps1 to reuse the checked-out repo source during automation"
  exit 1
fi

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

if ! search_file 'chezmoi apply --source \$chezmoiSource --force -v' "$windows_bootstrap"; then
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

if ! search_file 'Invoke-BestEffort -Phase "npm_global"' "$windows_bootstrap"; then
  echo "expected bootstrap.ps1 to record npm global install failures and continue in best-effort mode"
  exit 1
fi

if ! search_file 'Invoke-BestEffort -Phase "ai_cli"' "$windows_bootstrap"; then
  echo "expected bootstrap.ps1 to record AI CLI installer failures and continue in best-effort mode"
  exit 1
fi

if ! search_file '\$setupMode' "$windows_bootstrap" ||
  ! search_file 'DOTFILES_SETUP_MODE' "$windows_bootstrap" ||
  ! search_file 'Show-SetupFailureSummary' "$windows_bootstrap"; then
  echo "expected bootstrap.ps1 to support setup modes and print a final failure summary"
  exit 1
fi

if ! search_file '\$script:setupMode -eq "strict"' "$windows_bootstrap"; then
  echo "expected bootstrap.ps1 strict mode to preserve fail-fast installer behavior"
  exit 1
fi

if ! search_file 'DOTFILES_CHEZMOI_DIR' "$setup_playbook"; then
  echo "expected setup.yml to honor DOTFILES_CHEZMOI_DIR during CI"
  exit 1
fi

if ! search_file 'docker-ce-cli' "$repo_root/ansible/roles/linux_apps/tasks/linux-docker-desktop.yml"; then
  echo "expected Docker Desktop installers to provision docker-ce-cli"
  exit 1
fi

if ! search_file 'download\.docker\.com/linux/ubuntu' "$repo_root/ansible/roles/linux_apps/tasks/linux-docker-desktop.yml"; then
  echo "expected Ubuntu Docker Desktop installer to add the official Docker apt repository"
  exit 1
fi

if ! search_file 'download\.docker\.com/linux/fedora/docker-ce\.repo' "$repo_root/ansible/roles/linux_apps/tasks/linux-docker-desktop.yml"; then
  echo "expected Fedora Docker Desktop installer to add the official Docker dnf repository"
  exit 1
fi

if ! search_file '--nogpgcheck' "$repo_root/ansible/roles/linux_apps/tasks/linux-docker-desktop.yml"; then
  echo "expected Fedora Docker Desktop installer to allow Docker''s unsigned desktop RPM"
  exit 1
fi

if search_file 'apt_repository:' "$repo_root/ansible/roles/linux_apps/tasks/linux-docker-desktop.yml"; then
  echo "expected Ubuntu Docker Desktop installer to avoid the deprecated apt_repository module"
  exit 1
fi

if ! search_file '/etc/apt/sources\.list\.d/docker\.sources' "$repo_root/ansible/roles/linux_apps/tasks/linux-docker-desktop.yml"; then
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
  search_file 'ignore_errors: yes' "$devtools_npm_best_effort_task"; then
  echo "expected Flatpak and npm best-effort installers to record failures without ignore_errors"
  exit 1
fi

if ! search_file 'Install flatpak packages \(strict\)' "$flatpak_task" ||
  ! search_file 'Install flatpak packages \(best effort\)' "$flatpak_task" ||
  ! search_file 'dotfiles_setup_mode.*strict' "$flatpak_task" ||
  ! search_file 'dotfiles_setup_mode.*best_effort' "$flatpak_task" ||
  ! search_file 'phase.*flatpak_app' "$flatpak_best_effort_task" ||
  ! search_file 'dotfiles_setup_failures' "$flatpak_best_effort_task"; then
  echo "expected Flatpak installs to preserve strict mode and record per-app best-effort failures"
  exit 1
fi

if ! search_file 'Install or update global npm development tools \(strict\)' "$devtools_task_main" ||
  ! search_file 'Install or update global npm development tools \(best effort\)' "$devtools_task_main" ||
  ! search_file 'dotfiles_setup_mode.*strict' "$devtools_task_main" ||
  ! search_file 'dotfiles_setup_mode.*best_effort' "$devtools_task_main" ||
  ! search_file 'phase.*npm_global' "$devtools_npm_best_effort_task" ||
  ! search_file 'dotfiles_setup_failures' "$devtools_npm_best_effort_task" ||
  ! search_file 'dotfiles_setup_skipped' "$devtools_task_main"; then
  echo "expected npm globals to preserve strict mode, record per-package failures, and list skipped packages when npm is unavailable"
  exit 1
fi

if ! search_file 'https://chatgpt\.com/codex/install\.sh' "$ai_clis_data"; then
  echo "expected Codex Unix installer to use the current chatgpt.com installer URL"
  exit 1
fi

if search_file 'github\.com/openai/codex/releases/latest/download/install\.sh' "$ai_clis_data"; then
  echo "expected Codex Unix installer not to use the stale GitHub release installer URL"
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

if ! search_file 'install_unix_cli_best_effort\.yml' "$ai_tools_task_main" ||
  ! search_file 'dotfiles_setup_failures' "$ai_tools_unix_best_effort_task" ||
  ! search_file "dotfiles_setup_mode \\| default\\('best_effort'\\) == 'strict'" "$ai_tools_unix_best_effort_task"; then
  echo "expected AI CLI Unix installers to support strict and best-effort setup modes"
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

if ! search_file 'pacman-key --init' "$repo_root/ansible/roles/linux_apps/tasks/linux-warp.yml"; then
  echo "expected Arch Warp installer to initialize the pacman keyring when needed"
  exit 1
fi

if search_file "lookup\\('env', 'CI'\\)" "$setup_playbook"; then
  echo "expected setup.yml to use DOTFILES_CI only for lightweight CI mode"
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

if ! search_file 'include_role:' "$run_feature_task" || ! search_file 'features/\{\{ selected_feature \}\}' "$run_feature_task"; then
  echo "expected common flow to run selected feature roles by feature name"
  exit 1
fi

if ! search_file 'dotfiles_setup_mode' "$common_playbook" ||
  ! search_file 'DOTFILES_SETUP_MODE' "$common_playbook" ||
  ! search_file 'Show setup outcome summary' "$common_playbook" ||
  ! search_file 'dotfiles_setup_failures' "$common_playbook"; then
  echo "expected common flow to support setup modes and print a final outcome summary"
  exit 1
fi

if ! search_file '^remote_tmp = /tmp/ansible-\$\{USER\}/tmp$' "$ansible_config"; then
  echo "expected Ansible remote temp files to use /tmp so a full HOME does not block the final summary"
  exit 1
fi

if ! search_file 'DOTFILES_LOW_MEMORY' "$common_playbook" ||
  ! search_file 'DOTFILES_LOW_MEMORY_THRESHOLD_MB' "$common_playbook" ||
  ! search_file 'dotfiles_low_memory_setup' "$common_playbook" ||
  ! search_file 'name: low_memory' "$common_playbook"; then
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

if ! search_file 'one at a time.*Debian/Ubuntu low memory' "$debian_packages_task" ||
  ! search_file 'Acquire::Queue-Mode=access' "$debian_packages_task" ||
  ! search_file 'one at a time.*Fedora low memory' "$fedora_packages_task" ||
  ! search_file 'max_parallel_downloads=1' "$fedora_packages_task" ||
  ! search_file 'one at a time.*Archlinux low memory' "$arch_packages_task"; then
  echo "expected Linux package tasks to use serial low-memory install paths"
  exit 1
fi

if ! search_file 'apt_package' "$debian_packages_task" ||
  ! search_file 'dnf_package' "$fedora_packages_task" ||
  ! search_file 'pacman_package' "$arch_packages_task" ||
  ! search_file 'brew_package' "$macos_packages_task" ||
  ! search_file 'cask_package' "$macos_packages_task" ||
  ! search_file 'failed_when: false' "$debian_packages_task" ||
  ! search_file 'failed_when: false' "$fedora_packages_task" ||
  ! search_file 'failed_when: false' "$arch_packages_task" ||
  ! search_file 'failed_when: false' "$macos_packages_task"; then
  echo "expected best-effort direct package installs to record per-item failures"
  exit 1
fi

if ! search_file 'NODE_OPTIONS' "$ai_tools_unix_task" ||
  ! search_file 'NPM_CONFIG_JOBS' "$ai_tools_unix_task" ||
  ! search_file 'NODE_OPTIONS' "$devtools_task_main" ||
  ! search_file 'NPM_CONFIG_JOBS' "$devtools_task_main"; then
  echo "expected npm and AI CLI installers to cap Node/npm work in low-memory mode"
  exit 1
fi

if ! search_file 'Setup Outcome Summary' "$setup_outcome_task" ||
  ! search_file 'Installed or present after setup' "$setup_outcome_task" ||
  ! search_file 'Not installed or not configured' "$setup_outcome_task" ||
  ! search_file 'Errors:' "$setup_outcome_task"; then
  echo "expected setup outcome role to print installed, configured, missing, and error sections"
  exit 1
fi

for verifier in dpkg-query rpm pacman brew flatpak npm 'command -v'; do
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

if ! search_file 'dotfiles_setup_mode == '\''strict'\''' "$run_feature_task" ||
  ! search_file 'dotfiles_setup_mode == '\''best_effort'\''' "$run_feature_task" ||
  ! search_file 'dotfiles_setup_failures' "$run_feature_task"; then
  echo "expected feature execution helper to preserve strict mode and record best-effort failures"
  exit 1
fi

if ! search_file 'export PATH="\$HOME/\.local/bin:\$PATH"' "$workflow_file"; then
  echo "expected CI idempotency checks to find tools installed into HOME/.local/bin by bootstrap.sh"
  exit 1
fi

if ! search_file '--source' "$repo_root/ansible/roles/chezmoi/tasks/main.yml"; then
  echo "expected chezmoi ansible role to pass the resolved source directory explicitly"
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

if ! search_file 'lazygit_local_binary="\{\{ lookup\('\''env'\'', '\''HOME'\''\) \}\}/\.local/bin/lazygit"' "$lazygit_task"; then
  echo "expected lazygit check to prefer the local installed binary"
  exit 1
fi

if ! search_file 'lazygit_version_marker="\{\{ lookup\('\''env'\'', '\''HOME'\''\) \}\}/\.local/share/dotfiles/lazygit-version"' "$lazygit_task"; then
  echo "expected lazygit check to use a managed version marker"
  exit 1
fi

if ! search_file 'lazygit --version' "$lazygit_task"; then
  echo "expected lazygit check to fall back to PATH lookup"
  exit 1
fi

if ! search_file 'Ensure local metadata directory exists' "$lazygit_task"; then
  echo "expected lazygit install to create a metadata directory"
  exit 1
fi

if ! search_file 'Record installed lazygit version' "$lazygit_task"; then
  echo "expected lazygit install to record the installed version"
  exit 1
fi

if ! awk '
  /Create temporary directory for lazygit download/ { in_task = 1; next }
  /^    - name:/ && in_task { in_task = 0 }
  in_task && /changed_when: false/ { found = 1 }
  END { exit(found ? 0 : 1) }
' "$lazygit_task"; then
  echo "expected lazygit temporary download directory creation to be idempotency-neutral"
  exit 1
fi

if ! search_file 'changed_when: false' "$services_task_main"; then
  echo "expected managed user service activation to be idempotency-neutral in CI logs"
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

if ! search_file 'Check Idempotency' "$workflow_file"; then
  echo "expected ci.yml to include idempotency checks"
  exit 1
fi

if ! search_file 'chezmoi diff --source "\$PWD"' "$workflow_file"; then
  echo "expected ci.yml to verify managed-file idempotency with chezmoi diff"
  exit 1
fi

if ! search_file 'output_log="\$\(mktemp\)"' "$workflow_file"; then
  echo "expected ci.yml to write idempotency logs outside the repo source tree"
  exit 1
fi

if ! search_file 'chezmoi_diff="\$\(mktemp\)"' "$workflow_file"; then
  echo "expected ci.yml to write chezmoi diff output outside the repo source tree"
  exit 1
fi

echo "CI bootstrap regressions passed"
