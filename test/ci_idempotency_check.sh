#!/usr/bin/env bash
set -euo pipefail

profile="${1:?usage: ci_idempotency_check.sh <profile>}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.local/bin:$PATH"

output_log="$(mktemp)"
chezmoi_diff="$(mktemp)"
trap 'rm -f "$output_log" "$chezmoi_diff"' EXIT

cd "$repo_root"
./bootstrap.sh --profile "$profile" --strict | tee "$output_log"

if grep -qE "changed=[1-9]" "$output_log"; then
  echo "Idempotency test failed, changes were made on the second run"
  exit 1
fi

chezmoi diff --source "$repo_root" >"$chezmoi_diff"
if [ -s "$chezmoi_diff" ]; then
  cat "$chezmoi_diff"
  echo "Idempotency test failed, chezmoi diff reported changes after the second run"
  exit 1
fi

"$repo_root/test/ci_setup_report_check.sh"
