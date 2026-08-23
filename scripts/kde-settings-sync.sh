#!/usr/bin/env bash
#
# Capture and restore KDE Plasma settings.
#
#   capture  machine -> repo   copy the tracked settings into kde/settings/
#   apply    repo -> machine   write every stored setting that differs
#   diff     show which stored settings differ from the live ones
#   check    exit 0 when the machine already matches the repo
#
# KDE keeps its settings in INI files under ~/.config (kdeglobals, kwinrc,
# ...). Those files are a poor fit for chezmoi: KDE rewrites them atomically,
# which replaces a symlink with a plain file, and they mix preferences with
# runtime state such as window geometry, update stamps and per-screen tiling
# layouts. So this script stores a filtered copy of each tracked file in
# kde/settings/<file> and writes the entries back one key at a time with
# kwriteconfig6, leaving everything else in the live file alone.
#
# The stored files use KConfig's own INI syntax, including its escaping (a
# tab is \t, a backslash is \\), and nested groups are written the way KDE
# writes them: [Containments][2][Applets][23].
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$script_dir/.." && pwd)"
data_dir="$repo_dir/kde/settings"
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"

# The files `capture` reads. Any other file already present in kde/settings/
# is kept and re-captured too, so a hand-added file stays tracked.
tracked_files=(
  kdeglobals              # look and feel: colours, fonts, icons, single-click, ...
  kwinrc                  # window manager: desktops, effects, night light, tiling
  kwinrulesrc             # window rules
  kglobalshortcutsrc      # global shortcuts (only the ones changed from default)
  kxkbrc                  # keyboard layouts and options
  kcminputrc              # keyboard repeat, mouse and touchpad (per device)
  powerdevilrc            # power management: buttons, lid, sleep timers
  knighttimerc            # day/night schedule (Plasma 6.7+)
  kscreenlockerrc         # screen locking
  ksmserverrc             # session management: logout confirmation, restore
  plasma-localerc         # regional formats
  plasmarc                # plasma theme
  plasmanotifyrc          # notification settings
  krunnerrc               # KRunner
  klipperrc               # clipboard
  dolphinrc               # file manager
  konsolerc               # terminal
  baloofilerc             # file indexing
)

# Groups and keys that KDE rewrites on its own: update stamps, cache hashes,
# window geometry, per-machine identifiers. Restoring them is meaningless and
# capturing them would make every capture produce a dirty diff.
#
# Patterns are shell globs matched against "<file>:<group>" for groups and
# "<file>:<group>/<key>" for keys; nested groups read "Outer][Inner".
# shellcheck disable=SC2016  # $Version is KConfig's literal group name
runtime_groups=(
  '*:$Version'                      # kconf_update stamps
  '*:MainWindow'                    # window geometry and toolbar state
  '*:*Dialog*'                      # dialog sizes
  '*:LegacySession*'                # saved sessions
  '*:Session*'
  'kwinrc:Tiling*'                  # custom tiling layouts, keyed by desktop and screen UUID
  'kwinrc:SubSession*'
  'baloofilerc:General'             # database version and first-run flag
  'plasmanotifyrc:DoNotDisturb'     # the "until" timestamp of the current do-not-disturb
)
runtime_keys=(
  'kdeglobals:General/ColorSchemeHash'
  'kwinrc:Desktops/Id_*'            # virtual desktop UUIDs
  'kglobalshortcutsrc:ActivityManager/switch-to-activity-*'
  'kglobalshortcutsrc:*/_k_friendly_name'   # component labels kglobalaccel registers itself
  'plasmarc:Wallpapers/usersWallpapers'
  'dolphinrc:General/Version'
  'dolphinrc:General/ViewPropsTimestamp'
  'konsolerc:General/ConfigVersion'
  'klipperrc:General/Version'
  'krunnerrc:General/migrated'
)

log()  { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# Plasma 6 ships the *6 tools, Plasma 5 the *5 ones.
kwriteconfig_bin() {
  if have kwriteconfig6; then printf 'kwriteconfig6'
  elif have kwriteconfig5; then printf 'kwriteconfig5'
  else return 1
  fi
}

kreadconfig_bin() {
  if have kreadconfig6; then printf 'kreadconfig6'
  elif have kreadconfig5; then printf 'kreadconfig5'
  else return 1
  fi
}

# Turn a KConfig INI file into one "group<TAB>key<TAB>value" record per entry.
# Values keep their on-disk escaping, so they never contain a real tab.
# Nested groups are flattened to "Outer][Inner"; entries before any group
# header get an empty group.
parse_ini() {
  awk '
    /^[[:space:]]*$/ { next }
    /^#/ { next }
    /^\[/ {
      group = $0
      sub(/^\[/, "", group)
      sub(/\][[:space:]]*$/, "", group)
      next
    }
    index($0, "=") > 0 {
      position = index($0, "=")
      print group "\t" substr($0, 1, position - 1) "\t" substr($0, position + 1)
    }
  ' "$1"
}

matches_any() {
  local subject="$1" pattern
  shift
  for pattern in "$@"; do
    # shellcheck disable=SC2053  # the pattern is meant to be a glob
    [[ $subject == $pattern ]] && return 0
  done
  return 1
}

# Drop the records that carry runtime state rather than preferences.
filter_runtime_records() {
  local file="$1" group key value

  while IFS=$'\t' read -r group key value; do
    if matches_any "$file:$group" "${runtime_groups[@]}"; then
      continue
    fi
    if matches_any "$file:$group/$key" "${runtime_keys[@]}"; then
      continue
    fi
    # shellcheck disable=SC2016  # literal KConfig markers, not expansions
    case "$key" in
      *'[$d]'|*'[$i]'|*'[$e]')
        # Marker entries (deleted, immutable, shell-expanded) that
        # kwriteconfig cannot reproduce.
        warn "$file: skipping [$group] $key"
        continue
        ;;
    esac
    printf '%s\t%s\t%s\n' "$group" "$key" "$value"
  done
}

# Global shortcuts are stored as "active,default,description", and the file
# lists every shortcut KDE knows about. Keep only the ones that differ from
# their default, so the repo records intent rather than the whole registry.
filter_default_shortcuts() {
  awk -F '\t' '
    {
      value = $3
      gsub(/\\,/, "\001", value)
      count = split(value, parts, ",")
      if (count >= 3 && parts[1] == parts[2]) next
      print
    }
  '
}

# Read a tracked file and print its records, already filtered.
live_records() {
  local file="$1"
  local path="$config_home/$file"

  [ -f "$path" ] || return 0
  if [ "$file" = "kglobalshortcutsrc" ]; then
    parse_ini "$path" | filter_runtime_records "$file" | filter_default_shortcuts
  else
    parse_ini "$path" | filter_runtime_records "$file"
  fi
}

# Print records back as an INI file, with one header comment.
write_settings_file() {
  local file="$1" output="$2" group key value
  local current=$'\x01'  # a sentinel no group name can equal

  {
    cat <<HEADER
# KDE Plasma settings for ~/.config/$file, captured by scripts/kde-settings-sync.sh.
#
# Regenerate with:   ./scripts/kde-settings-sync.sh capture
# Restore with:      ./scripts/kde-settings-sync.sh apply
#
# Values use KConfig's own escaping (a tab is \\t, a backslash is \\\\).
HEADER
    while IFS=$'\t' read -r group key value; do
      if [ "$group" != "$current" ]; then
        printf '\n[%s]\n' "$group"
        current="$group"
      fi
      printf '%s=%s\n' "$key" "$value"
    done
  } >"$output"
}

stored_files() {
  local path
  for path in "$data_dir"/*; do
    [ -f "$path" ] || continue
    printf '%s\n' "${path##*/}"
  done
}

# The union of the tracked list and what is already stored, in that order.
capture_targets() {
  local file
  local -A seen=()
  for file in "${tracked_files[@]}"; do
    seen[$file]=1
    printf '%s\n' "$file"
  done
  while IFS= read -r file; do
    [ -n "${seen[$file]:-}" ] && continue
    printf '%s\n' "$file"
  done < <(stored_files)
}

cmd_capture() {
  mkdir -p "$data_dir"

  local file records count written=0 kept=0
  while IFS= read -r file; do
    if [ ! -f "$config_home/$file" ]; then
      if [ -f "$data_dir/$file" ]; then
        log "kept ${data_dir#"$repo_dir"/}/$file (no ~/.config/$file on this machine)"
        kept=$((kept + 1))
      fi
      continue
    fi
    records="$(live_records "$file")"
    if [ -z "$records" ]; then
      if [ -f "$data_dir/$file" ]; then
        log "kept ${data_dir#"$repo_dir"/}/$file (~/.config/$file holds only runtime state)"
        kept=$((kept + 1))
      fi
      continue
    fi
    count="$(printf '%s\n' "$records" | grep -c .)"
    printf '%s\n' "$records" | write_settings_file "$file" "$data_dir/$file"
    log "wrote $count setting(s) to ${data_dir#"$repo_dir"/}/$file"
    written=$((written + 1))
  done < <(capture_targets)

  [ "$written" -gt 0 ] || [ "$kept" -gt 0 ] || die "no tracked KDE settings found under $config_home - is this a KDE Plasma machine?"
  log "captured $written file(s), kept $kept"
}

# Undo KConfig's INI escaping so a value can be handed to kwriteconfig, which
# escapes it again on the way back. Unknown escapes are kept as they are:
# "\," is list-element quoting that KConfig resolves at a higher layer.
kconfig_unescape() {
  awk '
    {
      out = ""
      n = length($0)
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (c != "\\" || i == n) { out = out c; continue }
        next_char = substr($0, i + 1, 1)
        if (next_char == "s")      { out = out " ";  i++ }
        else if (next_char == "t") { out = out "\t"; i++ }
        else if (next_char == "n") { out = out "\n"; i++ }
        else if (next_char == "r") { out = out "\r"; i++ }
        else if (next_char == "\\") { out = out "\\"; i++ }
        else { out = out c }
      }
      printf "%s", out
    }
  ' <<<"$1"
}

# Build the --group arguments for a flattened group name.
group_args() {
  local group="$1" part
  local -a parts=()

  if [ -z "$group" ]; then
    printf '%s\n' "--group" "<default>"
    return 0
  fi

  while [ -n "$group" ]; do
    part="${group%%\]\[*}"
    parts+=("$part")
    if [ "$part" = "$group" ]; then
      break
    fi
    group="${group#*\]\[}"
  done

  for part in "${parts[@]}"; do
    printf '%s\n' "--group" "$part"
  done
}

# The effective value KDE sees for an entry (its whole config cascade, not
# just the user file), or nothing when kreadconfig is unavailable.
effective_value() {
  local file="$1" group="$2" key="$3" reader
  local -a args=()

  reader="$(kreadconfig_bin)" || return 1
  mapfile -t args < <(group_args "$group")
  "$reader" --file "$file" "${args[@]}" --key "$key" 2>/dev/null
}

# List every stored entry that does not match the machine, one
# "file<TAB>group<TAB>key<TAB>stored<TAB>live" line per mismatch. The fast
# path compares the stored file with the live file text; only entries that
# differ there are read back through kreadconfig, which resolves defaults
# that KDE leaves out of the user file.
mismatched_entries() {
  local file group key value live_value effective
  local -A live=()

  while IFS= read -r file; do
    live=()
    if [ -f "$config_home/$file" ]; then
      while IFS=$'\t' read -r group key value; do
        live["$group"$'\t'"$key"]="$value"
      done < <(parse_ini "$config_home/$file")
    fi

    while IFS=$'\t' read -r group key value; do
      live_value="${live["$group"$'\t'"$key"]-}"
      if [ -n "${live["$group"$'\t'"$key"]+set}" ] && [ "$live_value" = "$value" ]; then
        continue
      fi
      if effective="$(effective_value "$file" "$group" "$key")" &&
        [ "$effective" = "$(kconfig_unescape "$value")" ]; then
        continue
      fi
      printf '%s\t%s\t%s\t%s\t%s\n' "$file" "$group" "$key" "$value" "$live_value"
    done < <(parse_ini "$data_dir/$file")
  done < <(stored_files)
}

require_stored_settings() {
  [ -d "$data_dir" ] && [ -n "$(stored_files)" ] ||
    die "${data_dir#"$repo_dir"/} is empty - run 'capture' first"
}

cmd_apply() {
  require_stored_settings
  local writer
  writer="$(kwriteconfig_bin)" || die "kwriteconfig6 (or kwriteconfig5) is not installed - is this a KDE Plasma machine?"

  # --notify makes running applications reload the changed file (KF5 5.x+).
  local -a notify=()
  local writer_help
  writer_help="$("$writer" --help 2>&1 || true)"
  case "$writer_help" in
    *--notify*) notify=(--notify) ;;
  esac

  local file group key value live_value count=0 kwin_changed=0
  local -a args=()
  while IFS=$'\t' read -r file group key value live_value; do
    mapfile -t args < <(group_args "$group")
    "$writer" --file "$file" "${args[@]}" --key "$key" "${notify[@]}" -- "$(kconfig_unescape "$value")"
    log "  $file [$group] $key=$value"
    count=$((count + 1))
    [ "$file" = "kwinrc" ] && kwin_changed=1
  done < <(mismatched_entries)

  if [ "$count" -eq 0 ]; then
    log "KDE settings already match the repo"
    return 0
  fi
  log "wrote $count setting(s)"

  if [ "$kwin_changed" -eq 1 ] && session_running; then
    if have qdbus6; then
      qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
    elif have qdbus; then
      qdbus org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
    fi
  fi

  log ""
  log "Running applications were notified of the change; log out and back in for the rest (global shortcuts, power management, the session itself)."
}

session_running() {
  pgrep -u "$(id -u)" -x plasmashell >/dev/null 2>&1
}

cmd_diff() {
  require_stored_settings
  local file group key value live_value found=0

  while IFS=$'\t' read -r file group key value live_value; do
    if [ "$found" -eq 0 ]; then
      log "stored (${data_dir#"$repo_dir"/}) differs from live (~/.config):"
      found=1
    fi
    log "  $file [$group] $key"
    log "    stored: $value"
    log "    live:   ${live_value:-(unset)}"
  done < <(mismatched_entries)

  if [ "$found" -eq 0 ]; then
    log "KDE settings match the repo"
    return 0
  fi
  return 1
}

# Exit 0 when the machine already matches the repo, non-zero when `apply` has
# work to do. Used to keep the Ansible run idempotent.
cmd_check() {
  [ -d "$data_dir" ] && [ -n "$(stored_files)" ] || return 1
  [ -z "$(mismatched_entries)" ]
}

usage() {
  cat <<'USAGE'
Usage: kde-settings-sync.sh <capture|apply|diff|check>

  capture   Copy the tracked KDE settings from ~/.config into kde/settings/,
            without their runtime state, ready to commit.
  apply     Write every stored setting that differs to ~/.config with
            kwriteconfig6, leaving other settings alone.
  diff      Show which stored settings differ from the live ones.
  check     Exit 0 if the machine already matches the repo, non-zero otherwise.
USAGE
}

case "${1:-}" in
  capture) cmd_capture ;;
  apply)   cmd_apply ;;
  diff)    cmd_diff ;;
  check)   cmd_check ;;
  -h|--help|help|"") usage ;;
  *) usage >&2; exit 2 ;;
esac
