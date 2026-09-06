#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$script_dir/.." && pwd)"
data_file="$repo_dir/desktop_environment/kde/panels.json"

log()  { printf '%s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

dbus_tool() {
  local tool
  for tool in qdbus6 qdbus-qt6 qdbus dbus-send; do
    if have "$tool"; then
      printf '%s' "$tool"
      return 0
    fi
  done
  return 1
}

plasma_reachable() {
  local tool
  tool="$(dbus_tool)" || return 1
  if [ "$tool" = dbus-send ]; then
    dbus-send --session --print-reply --dest=org.kde.plasmashell /PlasmaShell org.freedesktop.DBus.Peer.Ping >/dev/null 2>&1
  else
    "$tool" org.kde.plasmashell /PlasmaShell >/dev/null 2>&1
  fi
}

require_session() {
  have python3 || die "python3 is required"
  dbus_tool >/dev/null || { log "no D-Bus client (qdbus6, qdbus-qt6, qdbus or dbus-send) is installed"; exit 2; }
  plasma_reachable || { log "plasmashell is not reachable on the session bus; run this inside a Plasma session"; exit 2; }
}

dbus_send_reply_py='
import sys
reply = sys.stdin.read().split("\n", 1)
body = reply[1].strip() if len(reply) > 1 else ""
if not (body.startswith("string \"") and body.endswith("\"")):
    sys.exit("unexpected dbus-send reply: " + body[:200])
sys.stdout.write(body[len("string \""):-1])
'

plasma_eval() {
  local tool
  tool="$(dbus_tool)"
  if [ "$tool" = dbus-send ]; then
    dbus-send --session --print-reply --dest=org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript string:"$1" | python3 -c "$dbus_send_reply_py"
  else
    "$tool" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$1"
  fi
}

dump_script='
var out = [];
panels().forEach(function (p) {
  p.currentConfigGroup = ["General"];
  var order = String(p.readConfig("AppletOrder", "")).split(";").filter(Boolean);
  var widgets = p.widgets();
  widgets.sort(function (a, b) {
    var ia = order.indexOf(String(a.id)), ib = order.indexOf(String(b.id));
    if (ia < 0) ia = order.length + a.id;
    if (ib < 0) ib = order.length + b.id;
    return ia - ib;
  });
  var panel = {
    location: p.location, alignment: p.alignment, hiding: p.hiding,
    lengthMode: p.lengthMode, minimumLength: p.minimumLength, maximumLength: p.maximumLength,
    offset: p.offset, height: p.height, floating: p.floating, opacity: p.opacity, widgets: []
  };
  widgets.forEach(function (w) {
    var config = {};
    w.currentConfigGroup = [];
    var groups = [""].concat(w.configGroups);
    groups.forEach(function (g) {
      w.currentConfigGroup = g === "" ? [] : [g];
      var keys = w.configKeys;
      if (!keys.length) return;
      config[g] = {};
      keys.forEach(function (k) { config[g][k] = String(w.readConfig(k)); });
    });
    panel.widgets.push({ plugin: w.type, config: config });
  });
  out.push(panel);
});
print(JSON.stringify(out));
'

filter_py='
import json, os, sys

runtime_root_keys = {"activityId", "formfactor", "immutability", "lastScreen", "location", "plugin", "wallpaperplugin", "popupHeight", "popupWidth"}
runtime_groups = {"ConfigDialog"}
runtime_keys = {("org.kde.plasma.systemtray", "General", "knownItems")}
home = os.path.expanduser("~")

def portable(value):
    if isinstance(value, str) and value.startswith(home + "/"):
        return "~" + value[len(home):]
    return value

panels = json.load(sys.stdin)
for panel in panels:
    if panel.get("lengthMode") == "fill":
        panel.pop("minimumLength", None)
        panel.pop("maximumLength", None)
    for widget in panel["widgets"]:
        config = {}
        for group, entries in widget["config"].items():
            if group in runtime_groups:
                continue
            kept = {}
            for key, value in entries.items():
                if group == "" and (key in runtime_root_keys or key.startswith("ItemGeometries")):
                    continue
                if (widget["plugin"], group, key) in runtime_keys:
                    continue
                kept[key] = portable(value)
            if kept:
                config[group] = kept
        widget["config"] = config
json.dump(panels, sys.stdout, indent=2, sort_keys=True)
sys.stdout.write("\n")
'

apply_py='
import json, os, sys

home = os.path.expanduser("~")

def js(value):
    return json.dumps(value)

def expand(value):
    if isinstance(value, str) and value.startswith("~/"):
        return home + value[1:]
    return value

panels = json.load(open(sys.argv[1]))
lines = ["panels().forEach(function (p) { p.remove(); });"]
for index, panel in enumerate(panels):
    p = "p%d" % index
    lines.append("var %s = new Panel;" % p)
    for prop in ("location", "alignment", "hiding", "lengthMode", "minimumLength", "maximumLength", "offset", "height", "floating", "opacity"):
        if prop in panel:
            lines.append("%s.%s = %s;" % (p, prop, js(panel[prop])))
    for windex, widget in enumerate(panel["widgets"]):
        w = "w%d_%d" % (index, windex)
        lines.append("var %s = %s.addWidget(%s);" % (w, p, js(widget["plugin"])))
        for group, entries in widget["config"].items():
            lines.append("%s.currentConfigGroup = %s;" % (w, js([] if group == "" else [group])))
            for key, value in entries.items():
                lines.append("%s.writeConfig(%s, %s);" % (w, js(key), js(expand(value))))
        lines.append("%s.reloadConfig();" % w)
    lines.append("%s.reloadConfig();" % p)
print("\n".join(lines))
'

live_panels() {
  plasma_eval "$dump_script" | python3 -c "$filter_py"
}

stored_panels() {
  [ -f "$data_file" ] || die "no stored panels at ${data_file#"$repo_dir"/}; run capture first"
  python3 -c 'import json, sys; json.dump(json.load(open(sys.argv[1])), sys.stdout, indent=2, sort_keys=True); sys.stdout.write("\n")' "$data_file"
}

run_capture() {
  require_session
  mkdir -p "$(dirname "$data_file")"
  live_panels >"$data_file"
  log "captured $(python3 -c 'import json, sys; print(len(json.load(open(sys.argv[1]))))' "$data_file") panel(s) to ${data_file#"$repo_dir"/}"
}

run_diff() {
  require_session
  local stored live
  stored="$(stored_panels)"
  live="$(live_panels)"
  if [ "$stored" = "$live" ]; then
    log "stored panels match the live layout"
    return 0
  fi
  diff -u --label "stored (${data_file#"$repo_dir"/})" --label "live (plasmashell)" <(printf '%s\n' "$stored") <(printf '%s\n' "$live") || true
  return 1
}

run_check() {
  require_session
  if [ "$(stored_panels)" = "$(live_panels)" ]; then
    log "stored panels match the live layout"
  else
    log "stored panels differ from the live layout"
    return 1
  fi
}

run_apply() {
  require_session
  [ -f "$data_file" ] || die "no stored panels at ${data_file#"$repo_dir"/}; run capture first"
  if [ "$(stored_panels)" = "$(live_panels)" ]; then
    log "stored panels already match the live layout"
    return 0
  fi
  plasma_eval "$(python3 -c "$apply_py" "$data_file")" >/dev/null
  log "applied $(python3 -c 'import json, sys; print(len(json.load(open(sys.argv[1]))))' "$data_file") panel(s) from ${data_file#"$repo_dir"/}"
}

case "${1:-}" in
  capture) run_capture ;;
  check)   run_check ;;
  diff)    run_diff ;;
  apply)   run_apply ;;
  *)
    printf 'usage: %s capture|check|diff|apply\n' "$(basename "$0")" >&2
    exit 2
    ;;
esac
