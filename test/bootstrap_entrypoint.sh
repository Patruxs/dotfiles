#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP="$REPO_ROOT/bootstrap.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

fail() {
  echo "$1" >&2
  exit 1
}

clean_env=(env -u DOTFILES_CI -u DOTFILES_PROFILE -u DOTFILES_DESKTOP -u DOTFILES_REPO -u DOTFILES_SETUP_MODE)

home="$tmpdir/early-abort"
mkdir -p "$home"
if "${clean_env[@]}" HOME="$home" bash "$BOOTSTRAP" --profile personal --desktop bogus >"$tmpdir/early-abort.log" 2>&1; then
  fail "expected bootstrap.sh to reject --desktop bogus"
fi
report="$home/.dotfiles_setup_report.md"
[ -f "$report" ] ||
  fail "expected bootstrap.sh to write the setup report when it stops at the first check after argument parsing, got: $(cat "$tmpdir/early-abort.log")"
grep -q '^- Result: Aborted: Invalid desktop: bogus\.' "$report" ||
  fail "expected the setup report to name the invalid desktop, got: $(cat "$report")"
echo "ok: a failure right after argument parsing still writes the setup report"

mkdir -p "$tmpdir/bin"
cat >"$tmpdir/bin/sudo" <<'SH'
#!/bin/sh
cat >/dev/null
exit 0
SH
chmod 0755 "$tmpdir/bin/sudo"

home="$tmpdir/piped"
mkdir -p "$home"
if "${clean_env[@]}" HOME="$home" PATH="$tmpdir/bin:$PATH" DOTFILES_CI=1 bash -s -- --profile personal --desktop none \
  < <(cat "$BOOTSTRAP") >"$tmpdir/piped.log" 2>&1; then
  fail "expected the piped bootstrap to stop because DOTFILES_REPO is unset, got: $(cat "$tmpdir/piped.log")"
fi
report="$home/.dotfiles_setup_report.md"
grep -q '^- Result: Aborted: DOTFILES_REPO is required' "$report" 2>/dev/null ||
  fail "expected bootstrap.sh piped into bash to keep running after a command that reads stdin, got: $(cat "$tmpdir/piped.log")"
echo "ok: bootstrap.sh piped into bash survives a command that reads the rest of stdin"

echo "bootstrap entrypoint checks passed"
