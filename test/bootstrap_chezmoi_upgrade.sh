#!/usr/bin/env bash
# shellcheck disable=SC2329  # the stubs below are called by the functions eval'd from bootstrap.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP="$REPO_ROOT/bootstrap.sh"

extract_function() {
  local function_name="$1"

  awk -v fn="$function_name" '
    $0 ~ "^" fn "\\(\\) \\{" { printing = 1 }
    printing { print }
    printing && $0 == "}" { exit }
  ' "$BOOTSTRAP"
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

fail() {
  echo "$1" >&2
  exit 1
}

for required in have latest_chezmoi_version installed_chezmoi_version upgrade_chezmoi; do
  definition="$(extract_function "$required")"
  [ -n "$definition" ] || fail "bootstrap.sh no longer defines $required"
  eval "$definition"
done

calls="$tmpdir/calls"
release_json='{"id":1,"tag_name":"v2.72.2","update_url":"/twpayne/chezmoi/releases/tag/v2.72.2"}'
original_path="$PATH"
output=""
status=0

curl() {
  printf 'curl %s\n' "$*" >>"$calls"
  [ -n "$release_json" ] || return 22
  printf '%s' "$release_json"
}

wget() {
  printf 'wget %s\n' "$*" >>"$calls"
  [ -n "$release_json" ] || return 8
  printf '%s' "$release_json"
}

write_chezmoi() {
  mkdir -p "$1"
  cat >"$1/chezmoi" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = upgrade ]; then
  echo "chezmoi upgrade" >>"$calls"
  exit 0
fi
echo "chezmoi version v$2, commit 0123456789abcdef, built at 2026-01-01T00:00:00Z, built by goreleaser"
EOF
  chmod 0755 "$1/chezmoi"
}

install_chezmoi_to_local_bin() {
  echo "installer" >>"$calls"
  write_chezmoi "$HOME/.local/bin" 2.72.2
}

run_upgrade() {
  HOME="$tmpdir/$1"
  PATH="$2:$original_path"
  : >"$calls"
  set +e
  output="$(set -e; upgrade_chezmoi 2>&1)"
  status=$?
  set -e
  if grep -q 'api\.github\.com' "$calls"; then
    fail "expected upgrade_chezmoi to stay off the rate-limited GitHub API, got: $(cat "$calls")"
  fi
}

write_chezmoi "$tmpdir/current/.local/bin" 2.72.2
run_upgrade current "$tmpdir/current/.local/bin"
[ "$status" -eq 0 ] || fail "expected an up-to-date chezmoi to pass, got status $status: $output"
grep -q '^curl .*Accept: application/json.* https://github\.com/twpayne/chezmoi/releases/latest$' "$calls" ||
  fail "expected the latest release to be read as JSON from github.com/twpayne/chezmoi/releases/latest, got: $(cat "$calls")"
if grep -qxE 'installer|chezmoi upgrade' "$calls"; then
  fail "expected no reinstall and no chezmoi upgrade when chezmoi is already the latest release"
fi

write_chezmoi "$tmpdir/outdated/.local/bin" 2.72.0
run_upgrade outdated "$tmpdir/outdated/.local/bin"
[ "$status" -eq 0 ] || fail "expected an outdated ~/.local/bin/chezmoi to upgrade, got status $status: $output"
grep -qx installer "$calls" || fail "expected an outdated ~/.local/bin/chezmoi to be reinstalled with the chezmoi installer"
if grep -qx 'chezmoi upgrade' "$calls"; then
  fail "expected ~/.local/bin/chezmoi to be upgraded without 'chezmoi upgrade', which calls the GitHub API"
fi

write_chezmoi "$tmpdir/packaged/usr/bin" 2.72.0
run_upgrade packaged "$tmpdir/packaged/usr/bin"
[ "$status" -eq 0 ] || fail "expected an outdated chezmoi outside ~/.local/bin to upgrade, got status $status: $output"
grep -qx 'chezmoi upgrade' "$calls" || fail "expected chezmoi outside ~/.local/bin to upgrade itself the way it was installed"
if grep -qx installer "$calls"; then
  fail "expected no ~/.local/bin reinstall when chezmoi lives elsewhere"
fi

release_json=""
write_chezmoi "$tmpdir/offline/.local/bin" 2.72.0
run_upgrade offline "$tmpdir/offline/.local/bin"
[ "$status" -ne 0 ] || fail "expected upgrade_chezmoi to fail when the latest release cannot be read"
printf '%s\n' "$output" | grep -q 'Could not read the latest chezmoi release' ||
  fail "expected a clear message when the latest release cannot be read, got: $output"
if grep -qxE 'installer|chezmoi upgrade' "$calls"; then
  fail "expected no upgrade attempt when the latest release cannot be read"
fi

release_json='{"id":1,"tag_name":"v2.72.2"}'
have() {
  [ "$1" != curl ] && command -v "$1" >/dev/null 2>&1
}
write_chezmoi "$tmpdir/wget/.local/bin" 2.72.2
run_upgrade wget "$tmpdir/wget/.local/bin"
[ "$status" -eq 0 ] || fail "expected the wget fallback to read the latest release, got status $status: $output"
grep -q '^wget .*--header=Accept: application/json .*https://github\.com/twpayne/chezmoi/releases/latest$' "$calls" ||
  fail "expected wget to read the latest release as JSON when curl is missing, got: $(cat "$calls")"

echo "bootstrap chezmoi upgrade checks passed"
