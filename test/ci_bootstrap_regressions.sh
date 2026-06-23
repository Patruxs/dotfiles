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
setup_playbook="$repo_root/ansible/playbooks/setup.yml"
chezmoi_bootstrap_script="$repo_root/.chezmoiscripts/run_once_before_00-bootstrap.sh.tmpl"

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

if ! search_file "reject\\('in', ci_excluded_system_packages\\)" "$packages_task"; then
  echo "expected CI package filtering to use ci_excluded_system_packages"
  exit 1
fi

for distro_task in "$debian_packages_task" "$fedora_packages_task" "$arch_packages_task"; do
  if ! search_file 'state: latest' "$distro_task"; then
    echo "expected ${distro_task##*/} to install the latest available distro packages"
    exit 1
  fi
done

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

if ! search_file 'Skipping system package refresh in CI\.' "$repo_root/bootstrap.sh"; then
  echo "expected bootstrap.sh to skip full system upgrades during CI"
  exit 1
fi

if ! search_file 'Skipping dotfiles repo refresh in CI\.' "$repo_root/bootstrap.sh"; then
  echo "expected bootstrap.sh to skip repo refresh in CI"
  exit 1
fi

if ! search_file 'script_dir' "$repo_root/bootstrap.sh"; then
  echo "expected bootstrap.sh to resolve the checked-out repo during CI"
  exit 1
fi

if ! search_file 'Skipping package installs in CI\.' "$windows_bootstrap"; then
  echo "expected bootstrap.ps1 to skip winget installs during CI"
  exit 1
fi

if ! search_file 'Skipping chezmoi self-upgrade in CI\.' "$windows_bootstrap"; then
  echo "expected bootstrap.ps1 to skip chezmoi self-upgrade in CI"
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

if ! search_file 'DOTFILES_CHEZMOI_DIR' "$setup_playbook"; then
  echo "expected setup.yml to honor DOTFILES_CHEZMOI_DIR during CI"
  exit 1
fi

if ! search_file 'export DOTFILES_CHEZMOI_DIR="\$chezmoi_dir"' "$repo_root/bootstrap.sh"; then
  echo "expected bootstrap.sh to export DOTFILES_CHEZMOI_DIR for ansible"
  exit 1
fi

if ! search_file '--source' "$repo_root/ansible/roles/chezmoi/tasks/main.yml"; then
  echo "expected chezmoi ansible role to pass the resolved source directory explicitly"
  exit 1
fi

if ! search_file_literal '{{- if ne .chezmoi.os "windows" }}' "$chezmoi_bootstrap_script"; then
  echo "expected chezmoi bootstrap script to skip Bash execution on Windows"
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

echo "CI bootstrap regressions passed"
