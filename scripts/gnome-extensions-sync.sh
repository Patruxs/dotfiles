#!/usr/bin/env bash
#
# Capture and restore GNOME Shell extension configuration.
#
#   capture  machine -> repo   dump the live extension settings into gnome/
#   apply    repo -> machine   install, configure and enable the stored extensions
#   diff     show how the live settings differ from the stored ones
#   check    exit 0 when the machine already matches the repo
#
# The stored state lives in two files:
#
#   gnome/extensions.dconf   a `dconf dump` of /org/gnome/shell/extensions/
#   gnome/extensions.yaml    which extensions are enabled, and where they came from
#
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$script_dir/.." && pwd)"
data_dir="$repo_dir/gnome"
settings_file="$data_dir/extensions.dconf"
manifest_file="$data_dir/extensions.yaml"

dconf_path="/org/gnome/shell/extensions/"
ego_base="https://extensions.gnome.org"

# Keys that GNOME rewrites on its own: cache stamps, "have I shown this nag yet"
# markers and session state. Restoring them is meaningless and capturing them
# makes every dump produce a dirty diff. A trailing slash excludes a whole group.
runtime_keys=(
  "blur-my-shell/rounded-blur-found"
  "forge/css-last-update"
  "forge/css-updated"
  "just-perfection/support-notifier-showed-version"
  "paperwm/last-used-display-server"
  "space-bar/state/"
)

log()  { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

require_dconf() {
  have dconf || die "dconf is not installed"
  have gsettings || die "gsettings is not installed"
}

user_ext_dir="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions"

# Where an extension lives, or nothing at all if it is not installed.
extension_origin() {
  local uuid="$1" dir
  [ -d "$user_ext_dir/$uuid" ] && { printf 'user'; return 0; }
  for dir in /usr/share/gnome-shell/extensions /usr/local/share/gnome-shell/extensions; do
    [ -d "$dir/$uuid" ] && { printf 'system'; return 0; }
  done
  return 1
}

# Turn a gsettings string array - ['a', 'b'] - into one UUID per line.
gsettings_list() {
  gsettings get org.gnome.shell "$1" 2>/dev/null |
    sed "s/^\[//; s/\]$//; s/', *'/\n/g; s/^'//; s/'$//" |
    sed "s/^ *//; s/ *$//" |
    grep -v '^$' || true
}

# Read a flat list out of the manifest. The file is written by this script, so
# the shape is fixed: two-space keys, four-space list items.
yaml_list() {
  [ -f "$manifest_file" ] || return 0
  awk -v want="$1" '
    $0 ~ "^  " want ":[[:space:]]*$" { inside = 1; next }
    inside && /^  [a-z_]+:/          { inside = 0 }
    inside && /^    - /              { sub(/^    - /, ""); print }
  ' "$manifest_file"
}

# Strip the runtime keys out of a dconf dump, dropping any group left empty.
filter_runtime_keys() {
  local excludes
  excludes="$(printf '%s\n' "${runtime_keys[@]}")"
  awk -v excludes="$excludes" '
    BEGIN {
      split(excludes, list, "\n")
      for (i in list) if (list[i] != "") drop[list[i]] = 1
    }
    /^\[/ {
      group = substr($0, 2, length($0) - 2)
      pending = $0
      next
    }
    /^[^=]+=/ {
      key = substr($0, 1, index($0, "=") - 1)
      if (drop[group "/" key] || drop[group "/"]) next
      if (pending != "") {
        if (started) print ""
        print pending
        pending = ""
        started = 1
      }
      print
    }
  '
}

cmd_capture() {
  require_dconf
  mkdir -p "$data_dir"

  local dump
  dump="$(dconf dump "$dconf_path")"
  [ -n "$dump" ] || die "dconf dump $dconf_path is empty - is this a GNOME session?"
  printf '%s\n' "$dump" | filter_runtime_keys > "$settings_file"
  log "wrote $(grep -c '=' "$settings_file") settings to ${settings_file#"$repo_dir"/}"

  local enabled=() disabled=() user_installed=() system_installed=() missing=()
  local uuid origin
  while IFS= read -r uuid; do
    if origin="$(extension_origin "$uuid")"; then
      enabled+=("$uuid")
      [ "$origin" = user ] && user_installed+=("$uuid") || system_installed+=("$uuid")
    else
      missing+=("$uuid")
    fi
  done < <(gsettings_list enabled-extensions)

  while IFS= read -r uuid; do
    if origin="$(extension_origin "$uuid")"; then
      disabled+=("$uuid")
      [ "$origin" = user ] && user_installed+=("$uuid") || system_installed+=("$uuid")
    else
      missing+=("$uuid")
    fi
  done < <(gsettings_list disabled-extensions)

  # Installed but referenced by neither list - still worth reinstalling.
  local dir
  for dir in "$user_ext_dir"/*/; do
    [ -d "$dir" ] || continue
    uuid="$(basename "$dir")"
    printf '%s\n' "${user_installed[@]:-}" | grep -qxF "$uuid" || user_installed+=("$uuid")
  done

  write_manifest
  log "wrote manifest to ${manifest_file#"$repo_dir"/}"
  log "  enabled: ${#enabled[@]}  disabled: ${#disabled[@]}  from extensions.gnome.org: ${#user_installed[@]}  from distro: ${#system_installed[@]}"
  if [ "${#missing[@]}" -gt 0 ]; then
    warn "skipped ${#missing[@]} UUID(s) listed in dconf but not installed: ${missing[*]}"
  fi
}

write_manifest() {
  {
    cat <<'HEADER'
# GNOME Shell extensions, captured by scripts/gnome-extensions-sync.sh.
#
# Regenerate with:   ./scripts/gnome-extensions-sync.sh capture
# Restore with:      ./scripts/gnome-extensions-sync.sh apply
#
# Per-extension settings live alongside this file in extensions.dconf.
gnome_extensions:
HEADER
    printf '  # Loaded by GNOME Shell at startup, in this order.\n'
    emit_ordered_list enabled "${enabled[@]:-}"
    printf '\n  # Installed but switched off.\n'
    emit_ordered_list disabled "${disabled[@]:-}"
    printf '\n  # Downloaded from extensions.gnome.org into ~/.local/share/gnome-shell/extensions.\n'
    printf '  # The apply mode fetches whichever of these are missing.\n'
    emit_ordered_list user_installed "${user_installed[@]:-}"
    printf '\n  # Shipped by distro packages. Listed for reference - install the package to get them.\n'
    emit_ordered_list system_installed "${system_installed[@]:-}"
  } > "$manifest_file"
}

# Keep enabled-extensions in its original order; that order decides load order.
emit_ordered_list() {
  local name="$1"; shift
  printf '  %s:\n' "$name"
  local item found=0
  local -A seen=()
  for item in "$@"; do
    [ -n "$item" ] || continue
    [ -n "${seen[$item]:-}" ] && continue
    seen[$item]=1
    printf '    - %s\n' "$item"
    found=1
  done
  [ "$found" -eq 1 ] || printf '    []\n'
}

shell_version() {
  gnome-shell --version 2>/dev/null | awk '{print $3}'
}

# Ask extensions.gnome.org for the download URL matching this shell version.
ego_download_url() {
  local uuid="$1" version="$2" response url
  response="$(curl -fsSL --get \
    --data-urlencode "uuid=$uuid" \
    --data-urlencode "shell_version=$version" \
    "$ego_base/extension-info/" 2>/dev/null)" || return 1
  url="$(printf '%s' "$response" |
    grep -o '"download_url"[[:space:]]*:[[:space:]]*"[^"]*"' |
    sed 's/.*"\(\/[^"]*\)"/\1/; s|\\/|/|g')"
  [ -n "$url" ] || return 1
  printf '%s%s' "$ego_base" "$url"
}

install_extension() {
  local uuid="$1" version url tmp
  version="$(shell_version)"
  [ -n "$version" ] || die "cannot determine the GNOME Shell version"

  url="$(ego_download_url "$uuid" "$version")" ||
    url="$(ego_download_url "$uuid" "${version%%.*}")" || {
      warn "no build of $uuid for GNOME Shell $version on extensions.gnome.org"
      return 1
    }

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  curl -fsSL "$url" -o "$tmp/pack.zip" || { warn "failed to download $uuid"; return 1; }
  gnome-extensions install --force "$tmp/pack.zip" || { warn "failed to install $uuid"; return 1; }
  log "  installed $uuid"
}

cmd_apply() {
  require_dconf
  [ -f "$settings_file" ] || die "${settings_file#"$repo_dir"/} not found - run 'capture' first"
  [ -f "$manifest_file" ] || die "${manifest_file#"$repo_dir"/} not found - run 'capture' first"

  # 1. Install anything missing, before its settings land.
  local uuid pending=()
  while IFS= read -r uuid; do
    extension_origin "$uuid" >/dev/null || pending+=("$uuid")
  done < <(yaml_list user_installed)

  if [ "${#pending[@]}" -gt 0 ]; then
    if have curl && have gnome-extensions; then
      log "installing ${#pending[@]} missing extension(s) from extensions.gnome.org"
      for uuid in "${pending[@]}"; do
        install_extension "$uuid" || true
      done
    else
      warn "curl and gnome-extensions are required to install: ${pending[*]}"
    fi
  fi

  local absent=()
  while IFS= read -r uuid; do
    extension_origin "$uuid" >/dev/null || absent+=("$uuid")
  done < <(yaml_list system_installed)
  if [ "${#absent[@]}" -gt 0 ]; then
    warn "not installed, and shipped by a distro package rather than extensions.gnome.org: ${absent[*]}"
  fi

  # 2. Load the settings while the extensions are still switched off, so none of
  #    them overwrites a stored value with its default on first activation.
  dconf load "$dconf_path" < "$settings_file"
  log "loaded $(grep -c '=' "$settings_file") settings into $dconf_path"

  # 3. Switch on whatever is actually present.
  local enable=() skipped=() disable=()
  while IFS= read -r uuid; do
    if extension_origin "$uuid" >/dev/null; then
      enable+=("$uuid")
    else
      skipped+=("$uuid")
    fi
  done < <(yaml_list enabled)

  while IFS= read -r uuid; do
    extension_origin "$uuid" >/dev/null && disable+=("$uuid")
  done < <(yaml_list disabled)

  gsettings set org.gnome.shell enabled-extensions "$(gvariant_array "${enable[@]:-}")"
  gsettings set org.gnome.shell disabled-extensions "$(gvariant_array "${disable[@]:-}")"
  log "enabled ${#enable[@]} extension(s)"
  [ "${#skipped[@]}" -gt 0 ] && warn "could not enable (not installed): ${skipped[*]}"

  log ""
  log "Log out and back in to load the extensions (GNOME Shell cannot be restarted in place under Wayland)."
}

# Build a GVariant string array literal from the arguments.
gvariant_array() {
  local out="" item
  for item in "$@"; do
    [ -n "$item" ] || continue
    [ -n "$out" ] && out+=", "
    out+="'$item'"
  done
  printf '[%s]' "$out"
}

cmd_diff() {
  require_dconf
  [ -f "$settings_file" ] || die "${settings_file#"$repo_dir"/} not found - run 'capture' first"
  local live
  live="$(mktemp)"
  trap 'rm -f "$live"' RETURN
  dconf dump "$dconf_path" | filter_runtime_keys > "$live"
  if diff -u --label "stored (${settings_file#"$repo_dir"/})" --label "live ($dconf_path)" \
      "$settings_file" "$live"; then
    log "extension settings match the repo"
  else
    return 1
  fi
}

# Exit 0 when the machine already matches the repo, non-zero when `apply` has
# work to do. Used to keep the Ansible run idempotent.
cmd_check() {
  require_dconf
  [ -f "$settings_file" ] && [ -f "$manifest_file" ] || return 1

  local live uuid
  live="$(mktemp)"
  trap 'rm -f "$live"' RETURN
  dconf dump "$dconf_path" | filter_runtime_keys > "$live"
  cmp -s "$settings_file" "$live" || return 1

  while IFS= read -r uuid; do
    extension_origin "$uuid" >/dev/null || return 1
  done < <(yaml_list user_installed)

  local enable=()
  while IFS= read -r uuid; do
    extension_origin "$uuid" >/dev/null && enable+=("$uuid")
  done < <(yaml_list enabled)
  [ "$(gsettings get org.gnome.shell enabled-extensions)" = "$(gvariant_array "${enable[@]:-}")" ]
}

usage() {
  cat <<'USAGE'
Usage: gnome-extensions-sync.sh <capture|apply|diff|check>

  capture   Dump the live GNOME extension settings and extension list into
            gnome/, ready to commit.
  apply     Install the stored extensions, load their settings and enable them.
  diff      Show how the live settings differ from the stored ones.
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
