#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() {
  echo "$1"
  exit 1
}

mkdir -p "$work/repo/scripts" "$work/bin" "$work/home"
cp "$REPO_ROOT/scripts/plasma-panels-sync.sh" "$work/repo/scripts/"
sync="$work/repo/scripts/plasma-panels-sync.sh"
stored="$work/repo/desktop_environment/kde/panels.json"
export HOME="$work/home"
export PATH="$work/bin:$PATH"
export FAKE_PLASMA_STATE="$work/plasma"
mkdir -p "$FAKE_PLASMA_STATE"

cat >"$work/bin/qdbus" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[ -f "$FAKE_PLASMA_STATE/down" ] && exit 1
[ "$#" -ge 4 ] || exit 0
script="$4"
if [[ "$script" == *"JSON.stringify(out)"* ]]; then
  cat "$FAKE_PLASMA_STATE/live.json"
else
  printf '%s\n' "$script" >"$FAKE_PLASMA_STATE/applied.js"
fi
EOF
chmod +x "$work/bin/qdbus"
ln -s "$work/bin/qdbus" "$work/bin/qdbus6"
ln -s "$work/bin/qdbus" "$work/bin/qdbus-qt6"

cat >"$FAKE_PLASMA_STATE/live.json" <<EOF
[{"location":"top","alignment":"center","hiding":"none","lengthMode":"fill","minimumLength":2560,"maximumLength":2560,"offset":0,"height":30,"floating":false,"opacity":"adaptive","widgets":[
  {"plugin":"org.kde.plasma.kicker","config":{"":{"popupHeight":"532","popupWidth":"308","immutability":"1"},"ConfigDialog":{"DialogHeight":"630"},"General":{"icon":"$HOME/.local/share/icons/dotfiles/archlinux-logo.png","systemFavorites":"suspend\\\\,reboot"}}},
  {"plugin":"org.kde.plasma.panelspacer","config":{}},
  {"plugin":"org.kde.plasma.systemtray","config":{"":{"activityId":"","formfactor":"0","lastScreen":"-1","plugin":"org.kde.plasma.systemtray"},"General":{"extraItems":"org.kde.plasma.clipboard","knownItems":"org.kde.plasma.clipboard,org.kde.plasma.volume"}}},
  {"plugin":"org.kde.plasma.digitalclock","config":{"":{"ItemGeometries-2560x1440":""},"Appearance":{"showSeconds":"Never"}}}
]}]
EOF

"$sync" capture >"$work/capture.out" || fail "capture failed: $(cat "$work/capture.out")"
grep -q '^captured 1 panel(s)' "$work/capture.out" || fail "capture did not report the panel: $(cat "$work/capture.out")"
[ -f "$stored" ] || fail "capture did not write the stored panels"

python3 - "$stored" <<'EOF' || exit 1
import json, sys
panels = json.load(open(sys.argv[1]))
panel = panels[0]
assert "minimumLength" not in panel and "maximumLength" not in panel, "fill panels must not store screen-sized lengths"
assert panel["height"] == 30 and panel["floating"] is False and panel["location"] == "top"
kicker, spacer, tray, clock = panel["widgets"]
assert kicker["plugin"] == "org.kde.plasma.kicker"
assert "" not in kicker["config"], "popup sizes and immutability are runtime state"
assert "ConfigDialog" not in kicker["config"], "dialog geometry is runtime state"
assert kicker["config"]["General"]["icon"] == "~/.local/share/icons/dotfiles/archlinux-logo.png", kicker["config"]
assert kicker["config"]["General"]["systemFavorites"] == "suspend\\,reboot"
assert spacer["config"] == {}
assert "" not in tray["config"]
assert tray["config"]["General"] == {"extraItems": "org.kde.plasma.clipboard"}, "knownItems is runtime state"
assert clock["config"] == {"Appearance": {"showSeconds": "Never"}}, "ItemGeometries is runtime state"
EOF

"$sync" check >"$work/check1.out" || fail "check must pass right after capture: $(cat "$work/check1.out")"
"$sync" apply >"$work/apply1.out" || fail "apply failed: $(cat "$work/apply1.out")"
grep -q 'already match' "$work/apply1.out" || fail "apply must be a no-op when the layout matches: $(cat "$work/apply1.out")"
[ ! -f "$FAKE_PLASMA_STATE/applied.js" ] || fail "apply must not touch plasmashell when the layout matches"

python3 - "$stored" <<'EOF'
import json, sys
panels = json.load(open(sys.argv[1]))
panels[0]["height"] = 36
panels[0]["widgets"][3]["config"]["Appearance"]["showSeconds"] = "Always"
json.dump(panels, open(sys.argv[1], "w"), indent=2, sort_keys=True)
EOF

if "$sync" check >"$work/check2.out"; then
  fail "check must fail when the stored layout differs"
fi
"$sync" diff >"$work/diff.out" || true
grep -q '^-.*"height": 36' "$work/diff.out" && grep -q '^+.*"height": 30' "$work/diff.out" || fail "diff must show the changed height: $(cat "$work/diff.out")"

"$sync" apply >"$work/apply2.out" || fail "apply failed: $(cat "$work/apply2.out")"
grep -q '^applied 1 panel(s)' "$work/apply2.out" || fail "apply did not report the panel: $(cat "$work/apply2.out")"
applied="$FAKE_PLASMA_STATE/applied.js"
[ -f "$applied" ] || fail "apply did not send a layout script to plasmashell"
grep -q 'panels().forEach(function (p) { p.remove(); });' "$applied" || fail "apply must remove the existing panels first"
grep -q '^var p0 = new Panel;' "$applied" || fail "apply must create the panel"
grep -q '^p0.location = "top";' "$applied" || fail "apply must set the panel location"
grep -q '^p0.height = 36;' "$applied" || fail "apply must set the panel height"
grep -q '^p0.floating = false;' "$applied" || fail "apply must set floating"
grep -q '^p0.lengthMode = "fill";' "$applied" || fail "apply must set the length mode"
grep -q 'minimumLength' "$applied" && fail "apply must not set screen-sized lengths for fill panels"
grep -q '^var w0_0 = p0.addWidget("org.kde.plasma.kicker");' "$applied" || fail "apply must add the launcher first"
grep -q '^var w0_3 = p0.addWidget("org.kde.plasma.digitalclock");' "$applied" || fail "apply must add the clock last"
grep -q "^w0_0.writeConfig(\"icon\", \"$HOME/.local/share/icons/dotfiles/archlinux-logo.png\");" "$applied" || fail "apply must expand ~ to the home directory: $(grep icon "$applied")"
grep -q '^w0_0.writeConfig("systemFavorites", "suspend\\\\,reboot");' "$applied" || fail "apply must keep KConfig escaping: $(grep systemFavorites "$applied")"
grep -q '^w0_2.writeConfig("extraItems", "org.kde.plasma.clipboard");' "$applied" || fail "apply must configure the system tray"
grep -q '^w0_3.writeConfig("showSeconds", "Always");' "$applied" || fail "apply must write the updated clock setting"

touch "$FAKE_PLASMA_STATE/down"
"$sync" check >"$work/check3.out" 2>&1 && fail "check must not pass without a Plasma session"
[ "$("$sync" check >/dev/null 2>&1; echo $?)" -eq 2 ] || fail "check must exit 2 without a Plasma session"
[ "$("$sync" apply >/dev/null 2>&1; echo $?)" -eq 2 ] || fail "apply must exit 2 without a Plasma session"
rm -f "$FAKE_PLASMA_STATE/down"

cat >"$work/bin/dbus-send" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[ -f "$FAKE_PLASMA_STATE/down" ] && exit 1
method=""
script=""
for arg in "$@"; do
  case "$arg" in
    string:*) script="${arg#string:}" ;;
    org.kde.PlasmaShell.evaluateScript|org.freedesktop.DBus.Peer.Ping) method="$arg" ;;
  esac
done
printf 'method return time=1.0 sender=:1.1 -> destination=:1.2 serial=1 reply_serial=2\n'
[ "$method" = org.kde.PlasmaShell.evaluateScript ] || exit 0
if [[ "$script" == *"JSON.stringify(out)"* ]]; then
  printf '   string "%s"\n' "$(cat "$FAKE_PLASMA_STATE/live.json" | tr -d '\n')"
else
  printf '%s\n' "$script" >"$FAKE_PLASMA_STATE/applied.js"
  printf '   string ""\n'
fi
EOF
chmod +x "$work/bin/dbus-send"
rm -f "$work/bin/qdbus" "$work/bin/qdbus6" "$work/bin/qdbus-qt6" "$FAKE_PLASMA_STATE/applied.js"
only="$work/only"
mkdir -p "$only"
for tool in bash sh python3 diff cat mkdir dirname basename printf env grep sed head tail sort tr rm; do
  ln -s "$(command -v "$tool")" "$only/$tool"
done
ln -s "$work/bin/dbus-send" "$only/dbus-send"
if PATH="$only" "$sync" check >"$work/check5.out" 2>&1; then
  fail "check via dbus-send must still see the stored layout differ: $(cat "$work/check5.out")"
fi
grep -q 'differ' "$work/check5.out" || fail "check via dbus-send did not compare layouts: $(cat "$work/check5.out")"
PATH="$only" "$sync" apply >"$work/apply3.out" 2>&1 || fail "apply via dbus-send failed: $(cat "$work/apply3.out")"
grep -q '^p0.height = 36;' "$FAKE_PLASMA_STATE/applied.js" || fail "apply via dbus-send did not send the layout script"
rm -f "$only/dbus-send"
[ "$(PATH="$only" "$sync" check >/dev/null 2>&1; echo $?)" -eq 2 ] || fail "check must exit 2 when no D-Bus client is installed"

if "$sync" >/dev/null 2>&1; then
  fail "running without a subcommand must fail"
fi

echo "plasma panels sync passed"
