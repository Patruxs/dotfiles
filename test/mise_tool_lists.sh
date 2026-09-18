#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
conf_dir="$repo_root/home/dot_config/mise/conf.d"

failures=0
fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

if ! command -v chezmoi >/dev/null 2>&1; then
  echo "chezmoi is required for the mise tool list checks." >&2
  exit 1
fi

if ! ls "$conf_dir"/*.toml >/dev/null 2>&1; then
  fail "no mise tool lists found in ${conf_dir#"$repo_root"/}"
  exit 1
fi

profile_features="$(awk '/^features:/ { in_features = 1; next } /^[^ ]/ { in_features = 0 } in_features && /^  - [a-z0-9_]+$/ { print $2 }' "$repo_root"/ansible/vars/profiles/*.yml | sort -u)"
for list in "$conf_dir"/*.toml; do
  feature="$(basename "$list" .toml)"
  if ! grep -Fxq "$feature" <<<"$profile_features"; then
    fail "${list#"$repo_root"/} is not named after a feature any profile selects"
  fi
  if ! grep -Fxq '[tools]' "$list"; then
    fail "${list#"$repo_root"/} has no [tools] table"
  fi
  if ! awk '
    /^[[:space:]]*$/ || /^[[:space:]]*#/ || /^\[tools\]$/ { next }
    !/^("[^"]+"|[A-Za-z0-9_.:@\/-]+) = "latest"$/ { bad = 1; print FILENAME ": " $0 }
    END { exit(bad ? 1 : 0) }
  ' "$list"; then
    fail "${list#"$repo_root"/} requests something other than \"latest\" (no pinned versions, no option tables)"
  fi
done

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$tmpdir/home" "$tmpdir/cache"

HOME="$tmpdir/home" DOTFILES_CI=1 CHEZMOI_GPG_RECIPIENT="" chezmoi init \
  --source "$repo_root" \
  --destination "$tmpdir/home" \
  --config "$tmpdir/chezmoi.toml" \
  --cache "$tmpdir/cache" \
  --persistent-state "$tmpdir/chezmoi-state.boltdb" >/dev/null

managed_mise_paths() {
  HOME="$tmpdir/home" DOTFILES_CI=1 chezmoi managed \
    --source "$repo_root" \
    --destination "$tmpdir/home" \
    --config "$tmpdir/chezmoi.toml" \
    --cache "$tmpdir/cache" \
    --persistent-state "$tmpdir/chezmoi-state.boltdb" \
    --override-data "{\"dotfiles_features\":$1}" | grep -E '^\.config/mise(/|$)' || true
}

expect_lists() {
  local features="$1" expected="$2" actual
  actual="$(managed_mise_paths "$features" | { grep -E '^\.config/mise/conf\.d/.+\.toml$' || true; } | sed -E 's|^\.config/mise/conf\.d/||; s|\.toml$||' | sort | tr '\n' ' ' | sed 's/ $//')"
  if [ "$actual" != "$expected" ]; then
    fail "features $features manage mise tool lists [$actual], expected [$expected]"
  else
    echo "ok: features $features manage mise tool lists [$expected]"
  fi
}

for features in '[]' '["core_cli","ai_clis"]'; do
  if [ -n "$(managed_mise_paths "$features")" ]; then
    fail "features $features manage something under .config/mise although mise is not selected: $(managed_mise_paths "$features" | tr '\n' ' ')"
  else
    echo "ok: features $features manage nothing under .config/mise"
  fi
done

if ! managed_mise_paths '["mise"]' | grep -Fxq '.config/mise/conf.d'; then
  fail 'features ["mise"] do not manage the .config/mise/conf.d directory'
fi
expect_lists '["mise"]' ''
expect_lists '["mise","core_cli"]' 'core_cli'
expect_lists '["mise","core_cli","ai_clis"]' 'ai_clis core_cli'

all_features="$(printf '%s\n' "$profile_features" | sed 's/.*/"&"/' | paste -sd, -)"
all_lists="$(for list in "$conf_dir"/*.toml; do basename "$list" .toml; done | sort | tr '\n' ' ' | sed 's/ $//')"
expect_lists "[$all_features]" "$all_lists"

if [ "$failures" -ne 0 ]; then
  echo "$failures mise tool list check(s) failed" >&2
  exit 1
fi
echo "mise tool list checks passed"
