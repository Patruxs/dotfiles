#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
packages_task="$repo_root/ansible/roles/packages/tasks/main.yml"
lazygit_task="$repo_root/ansible/roles/git_tools/tasks/linux-lazygit.yml"

if ! rg -q "^  vars:$" "$packages_task"; then
  echo "expected Merge package lists task to declare task-local vars"
  exit 1
fi

if ! rg -q "^    ci_excluded_system_packages:$" "$packages_task"; then
  echo "expected CI system package exclusion list in task-local vars"
  exit 1
fi

for package in flatpak docker docker.io moby-engine; do
  if ! rg -q "^[[:space:]]+- $package$" "$packages_task"; then
    echo "expected $package to be excluded from CI system packages"
    exit 1
  fi
done

if ! rg -q "reject\\('in', ci_excluded_system_packages\\)" "$packages_task"; then
  echo "expected CI package filtering to use ci_excluded_system_packages"
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

if ! rg -q 'lazygit_local_binary="\{\{ lookup\('\''env'\'', '\''HOME'\''\) \}\}/\.local/bin/lazygit"' "$lazygit_task"; then
  echo "expected lazygit check to prefer the local installed binary"
  exit 1
fi

if ! rg -q 'lazygit --version' "$lazygit_task"; then
  echo "expected lazygit check to fall back to PATH lookup"
  exit 1
fi

echo "CI bootstrap regressions passed"
