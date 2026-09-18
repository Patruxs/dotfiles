#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

failures=0
fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/repo/scripts" "$work/bin" "$work/state" "$work/data/gnome-shell/extensions"
cp "$repo_root/scripts/gnome-extensions-sync.sh" "$work/repo/scripts/"
sync="$work/repo/scripts/gnome-extensions-sync.sh"
stored_dir="$work/repo/desktop_environment/gnome"

cat >"$work/bin/dconf" <<'SH'
#!/usr/bin/env bash
case "$1" in
  dump) cat "$FAKE_STATE/dconf" 2>/dev/null || true ;;
  load) cat >"$FAKE_STATE/dconf" ;;
  *) exit 2 ;;
esac
SH
cat >"$work/bin/gsettings" <<'SH'
#!/usr/bin/env bash
case "$1" in
  get) cat "$FAKE_STATE/$3" 2>/dev/null || echo "@as []" ;;
  set) printf '%s\n' "$4" >"$FAKE_STATE/$3" ;;
  *) exit 2 ;;
esac
SH
chmod +x "$work/bin/dconf" "$work/bin/gsettings"

run_sync() {
  env PATH="$work/bin:/usr/bin:/bin" FAKE_STATE="$work/state" XDG_DATA_HOME="$work/data" HOME="$work/home" bash "$sync" "$@"
}

mkdir -p "$work/data/gnome-shell/extensions/alpha@example" "$work/data/gnome-shell/extensions/beta@example"
cat >"$work/state/dconf" <<'DCONF'
[alpha]
size=3

[forge]
css-last-update=uint32 37
gap=4

[space-bar/state]
version=1
DCONF
echo "['alpha@example', 'ghost@example']" >"$work/state/enabled-extensions"
echo "['beta@example']" >"$work/state/disabled-extensions"

if run_sync check >/dev/null 2>&1; then
  fail "check passed before anything was captured"
else
  echo "ok: check fails when nothing is stored"
fi

run_sync capture >/dev/null 2>"$work/capture.err" || fail "capture failed: $(cat "$work/capture.err")"

if grep -q 'css-last-update' "$stored_dir/extensions.dconf" || grep -q 'space-bar/state' "$stored_dir/extensions.dconf"; then
  fail "capture kept runtime keys GNOME rewrites on its own"
else
  echo "ok: capture drops runtime keys and groups left empty"
fi
if grep -qx 'gap=4' "$stored_dir/extensions.dconf" && grep -qx 'size=3' "$stored_dir/extensions.dconf"; then
  echo "ok: capture keeps real settings"
else
  fail "capture lost real settings"
fi
if grep -q 'ghost@example' "$stored_dir/extensions.yaml"; then
  fail "capture recorded an extension that is not installed"
else
  echo "ok: capture skips UUIDs that are not installed"
fi
if grep -q 'ghost@example' "$work/capture.err"; then
  echo "ok: capture warns about the skipped UUID"
else
  fail "capture did not warn about the skipped UUID"
fi

echo "['alpha@example']" >"$work/state/enabled-extensions"
if run_sync check; then
  echo "ok: check passes when the machine matches the stored state"
else
  fail "check failed on a machine that matches the stored state"
fi

before="$(cat "$stored_dir/extensions.dconf" "$stored_dir/extensions.yaml")"
run_sync capture >/dev/null 2>&1
if [ "$before" = "$(cat "$stored_dir/extensions.dconf" "$stored_dir/extensions.yaml")" ]; then
  echo "ok: capturing twice produces the same files"
else
  fail "a second capture changed the stored files"
fi

sed -i 's/^gap=4$/gap=9/' "$work/state/dconf"
if run_sync check; then
  fail "check passed although a live setting differs"
else
  echo "ok: check fails when a live setting differs"
fi
if run_sync diff >"$work/diff.out" 2>&1; then
  fail "diff exited 0 although a live setting differs"
elif grep -q '^+gap=9$' "$work/diff.out"; then
  echo "ok: diff shows the differing setting"
else
  fail "diff did not show the differing setting"
fi

echo "[]" >"$work/state/enabled-extensions"
run_sync apply >/dev/null 2>&1 || fail "apply failed"
if grep -qx 'gap=4' "$work/state/dconf"; then
  echo "ok: apply loads the stored settings"
else
  fail "apply did not load the stored settings"
fi
if [ "$(cat "$work/state/enabled-extensions")" = "['alpha@example']" ] && [ "$(cat "$work/state/disabled-extensions")" = "['beta@example']" ]; then
  echo "ok: apply enables and disables the stored extensions"
else
  fail "apply wrote enabled=$(cat "$work/state/enabled-extensions") disabled=$(cat "$work/state/disabled-extensions")"
fi
if run_sync check; then
  echo "ok: check passes after apply"
else
  fail "check failed right after apply"
fi

rm -rf "$work/data/gnome-shell/extensions/beta@example"
if run_sync check; then
  fail "check passed although a stored extension is not installed"
else
  echo "ok: check fails when a stored extension is missing"
fi

echo "@as []" >"$work/state/enabled-extensions"
echo "@as []" >"$work/state/disabled-extensions"
run_sync capture >/dev/null 2>"$work/capture-empty.err" || fail "capture failed with no enabled extensions: $(cat "$work/capture-empty.err")"
if grep -q '@as' "$work/capture-empty.err" "$stored_dir/extensions.yaml"; then
  fail "capture read GNOME's empty-array marker '@as []' as an extension UUID"
else
  echo "ok: capture reads '@as []' as an empty extension list"
fi
if run_sync check; then
  echo "ok: check passes when no extension is enabled"
else
  fail "check failed on a machine with no enabled extensions, which gsettings reports as '@as []'"
fi

if [ "$failures" -gt 0 ]; then
  echo "gnome extensions sync failed: $failures" >&2
  exit 1
fi
echo "gnome extensions sync passed"
