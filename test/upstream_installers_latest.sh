#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scripts_dir="$repo_root/home/.chezmoiscripts"

failures=0
fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

if grep -nE 'raw\.githubusercontent\.com/[^/ ]+/[^/ ]+/v?[0-9]+\.[0-9]+' "$scripts_dir"/*.tmpl; then
  fail "an installer URL above pins a version; use the upstream default branch so the installer itself stays current"
fi
if grep -nE 'expected_sha256|sha256sum|shasum' "$scripts_dir"/*.tmpl; then
  fail "an installer above is pinned by checksum; upstream changes would break the install instead of being picked up"
fi

installer_urls="$(grep -ohE 'https://[^ "'"'"')]+/install\.sh' "$scripts_dir"/*.sh.tmpl | sort -u)"
if [ -z "$installer_urls" ]; then
  fail "no upstream installer URLs found under ${scripts_dir#"$repo_root"/}"
fi

if ! curl -fsSL --max-time 30 -o /dev/null https://raw.githubusercontent.com/ 2>/dev/null \
  && ! curl -fsSL --max-time 30 -o /dev/null https://github.com/ 2>/dev/null; then
  echo "No network access to GitHub; skipping the live upstream installer checks."
  [ "$failures" -eq 0 ] || exit 1
  exit 0
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

for url in $installer_urls; do
  name="$(printf '%s' "$url" | sed -E 's|https://||; s|/install\.sh$||; s|[^A-Za-z0-9]+|-|g')"
  if ! curl -fsSL --max-time 30 "$url" >"$tmpdir/$name.sh"; then
    fail "$url is not downloadable"
    continue
  fi
  if grep -Fq 'releases/latest' "$tmpdir/$name.sh"; then
    echo "ok: $url resolves the latest release at run time"
  else
    fail "$url no longer resolves the latest release (expected a 'releases/latest' lookup); review the upstream installer"
  fi
done

if [ "$failures" -ne 0 ]; then
  echo "$failures upstream installer check(s) failed" >&2
  exit 1
fi
echo "Upstream installer checks passed"
