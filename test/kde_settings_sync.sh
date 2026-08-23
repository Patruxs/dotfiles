#!/usr/bin/env bash
# Regression test for scripts/kde-settings-sync.sh: capture must drop KDE's
# runtime state and default shortcuts, check/diff must see exactly the stored
# entries, and apply must write only what differs and leave the rest alone.
#
# The capture/check/diff half runs everywhere. The apply half needs
# kwriteconfig6 (or kwriteconfig5) and is skipped, with a message, where KDE
# is not installed.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# A throwaway repository layout, so the script resolves its data dir there.
mkdir -p "$work/repo/scripts" "$work/config"
cp "$REPO_ROOT/scripts/kde-settings-sync.sh" "$work/repo/scripts/"
sync="$work/repo/scripts/kde-settings-sync.sh"
stored="$work/repo/kde/settings"
export XDG_CONFIG_HOME="$work/config"
export HOME="$work/home"
mkdir -p "$HOME"

fail() {
  echo "$1"
  exit 1
}

# Live files mixing preferences with the runtime state KDE rewrites itself.
cat >"$XDG_CONFIG_HOME/kwinrc" <<'EOF'
[$Version]
update_info=kwin.upd:replace-scalein-with-scale

[Desktops]
Id_1=771c4a49-0de0-4dc1-891b-6af181db414c
Number=2
Rows=1

[NightColor]
Active=true
NightTemperature=4700

[Tiling][771c4a49-0de0-4dc1-891b-6af181db414c][dc81ac08-2d1b-4f82-84ee-9040db5ec3f6]
padding=4
tiles={"layoutDirection":"horizontal","tiles":[{"width":0.25}]}
EOF
cat >"$XDG_CONFIG_HOME/kglobalshortcutsrc" <<'EOF'
[ActivityManager]
switch-to-activity-0d1f8a0e=none,none,Switch to activity "Default"

[kwin]
_k_friendly_name=KWin
Overview=Meta+W,Meta+W,Toggle Overview
Walk Through Windows=Alt+Tab\tMeta+Tab,Alt+Tab\tMeta+Tab,Walk Through Windows
Window Close=Meta+Q,Alt+F4,Close Window

[services][org.kde.konsole.desktop]
_launch=Ctrl+Alt+T
EOF
cat >"$XDG_CONFIG_HOME/kdeglobals" <<'EOF'
[General]
ColorSchemeHash=7715fd9c409e8efa0516fd38da43c1c19bb12d96
fixed=Hack,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1

[KDE]
SingleClick=false

[KFileDialog Settings]
Speedbar Width=157

[DirSelect Dialog]
DirSelectDialog Size=800,600
EOF
cat >"$XDG_CONFIG_HOME/dolphinrc" <<'EOF'
[General]
Version=202
ViewPropsTimestamp=2026,8,23,7,54,35.933

[MainWindow]
MenuBar=Disabled
EOF

# --- capture ---------------------------------------------------------------

"$sync" capture >/dev/null

[ -f "$stored/kwinrc" ] || fail "capture did not write kde/settings/kwinrc"
[ -f "$stored/kglobalshortcutsrc" ] || fail "capture did not write kde/settings/kglobalshortcutsrc"
[ -f "$stored/kdeglobals" ] || fail "capture did not write kde/settings/kdeglobals"
[ ! -e "$stored/dolphinrc" ] || fail "capture stored dolphinrc although it held only runtime state"
[ ! -e "$stored/kxkbrc" ] || fail "capture invented a file that does not exist on the machine"

stored_entries() {
  grep -vE '^(#|\[|$)' "$stored/$1" | LC_ALL=C sort
}

if [ "$(stored_entries kwinrc | tr '\n' ' ')" != "Active=true NightTemperature=4700 Number=2 Rows=1 " ]; then
  fail "kwinrc capture kept runtime state or lost a preference: $(stored_entries kwinrc | tr '\n' ' ')"
fi
grep -q '^\[Tiling' "$stored/kwinrc" && fail "capture kept a kwinrc Tiling group"
grep -q '^\[[$]Version\]' "$stored/kwinrc" && fail "capture kept the [\$Version] group"
grep -q '^Id_1=' "$stored/kwinrc" && fail "capture kept a virtual desktop UUID"

if [ "$(stored_entries kglobalshortcutsrc | tr '\n' ' ')" != "Window Close=Meta+Q,Alt+F4,Close Window _launch=Ctrl+Alt+T " ]; then
  fail "shortcut capture should keep only non-default shortcuts: $(stored_entries kglobalshortcutsrc | tr '\n' ' ')"
fi
grep -q '^\[services\]\[org.kde.konsole.desktop\]$' "$stored/kglobalshortcutsrc" || fail "nested group header was not preserved"

if [ "$(stored_entries kdeglobals | tr '\n' ' ')" != "SingleClick=false fixed=Hack,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1 " ]; then
  fail "kdeglobals capture kept a hash or dialog state: $(stored_entries kdeglobals | tr '\n' ' ')"
fi

head -1 "$stored/kwinrc" | grep -q '^# KDE Plasma settings for ~/.config/kwinrc' || fail "stored file lacks its header comment"

# A second capture must be a no-op.
before="$(cat "$stored/kwinrc" "$stored/kglobalshortcutsrc" "$stored/kdeglobals")"
"$sync" capture >/dev/null
after="$(cat "$stored/kwinrc" "$stored/kglobalshortcutsrc" "$stored/kdeglobals")"
[ "$before" = "$after" ] || fail "a second capture changed the stored files"

# A stored file with no live counterpart is kept, not deleted.
printf '[Layout]\nLayoutList=us\n' >"$stored/kxkbrc"
capture_output="$("$sync" capture)"
printf '%s\n' "$capture_output" | grep -q 'kept kde/settings/kxkbrc' || fail "capture did not keep a stored file that is absent on this machine: $capture_output"
[ -f "$stored/kxkbrc" ] || fail "capture deleted kde/settings/kxkbrc"
rm "$stored/kxkbrc"

# --- check and diff --------------------------------------------------------

"$sync" check || fail "check should pass right after capture"
"$sync" diff >"$work/diff.out" || fail "diff should exit 0 right after capture"
grep -q 'match the repo' "$work/diff.out" || fail "diff should report a match right after capture"

sed -i 's/^Number=2$/Number=3/' "$stored/kwinrc"
printf '\n[Extra]\nvalue=a\\\\b\\ttab\n' >>"$stored/kwinrc"

if "$sync" check; then
  fail "check should fail when a stored value differs"
fi
diff_output="$("$sync" diff || true)"
printf '%s\n' "$diff_output" | grep -q 'kwinrc \[Desktops\] Number' || fail "diff did not list the changed entry: $diff_output"
printf '%s\n' "$diff_output" | grep -q 'kwinrc \[Extra\] value' || fail "diff did not list the missing entry: $diff_output"
printf '%s\n' "$diff_output" | grep -q 'NightColor' && fail "diff listed an entry that matches"

# An empty repo is not a match.
mv "$stored" "$stored.bak"
if "$sync" check 2>/dev/null; then
  fail "check should fail with no stored settings"
fi
mv "$stored.bak" "$stored"

# --- apply -----------------------------------------------------------------

if ! command -v kwriteconfig6 >/dev/null 2>&1 && ! command -v kwriteconfig5 >/dev/null 2>&1; then
  echo "kde settings sync passed (apply skipped: kwriteconfig6 is not installed)"
  exit 0
fi

"$sync" apply >/dev/null

"$sync" check || fail "check should pass right after apply"
grep -q '^Number=3$' "$XDG_CONFIG_HOME/kwinrc" || fail "apply did not write the changed value"
grep -q '^value=a\\\\b\\ttab$' "$XDG_CONFIG_HOME/kwinrc" || fail "apply did not round-trip KConfig escaping: $(grep '^value=' "$XDG_CONFIG_HOME/kwinrc")"
grep -q '^Id_1=771c4a49' "$XDG_CONFIG_HOME/kwinrc" || fail "apply removed an untracked live entry"
grep -q '^\[Tiling\]' "$XDG_CONFIG_HOME/kwinrc" || fail "apply removed an untracked live group"
grep -q '^update_info=' "$XDG_CONFIG_HOME/kwinrc" || fail "apply removed the \$Version stamp"

# Apply is idempotent and writes nothing the second time.
apply_output="$("$sync" apply)"
printf '%s\n' "$apply_output" | grep -q 'already match' || fail "a second apply should find nothing to write: $apply_output"

# Nested groups and values starting with a dash reach kwriteconfig intact.
printf '[Containments][2][Applets][23][Configuration][Appearance]\nuse24hFormat=2\n\n[Libinput][1][2][Touchpad]\nPointerAcceleration=-0.26\n' >"$stored/plasma-test-rc"
"$sync" apply >/dev/null
grep -q '^\[Containments\]\[2\]\[Applets\]\[23\]\[Configuration\]\[Appearance\]$' "$XDG_CONFIG_HOME/plasma-test-rc" || fail "nested group was not written as KDE writes it"
grep -q '^PointerAcceleration=-0.26$' "$XDG_CONFIG_HOME/plasma-test-rc" || fail "a value starting with a dash was not written"
"$sync" check || fail "check should pass after applying nested groups"

echo "kde settings sync passed"
