#!/usr/bin/env bash
set -euo pipefail

data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
github_api="${DOTFILES_GITHUB_API:-https://api.github.com}"
github_web="${DOTFILES_GITHUB_WEB:-https://github.com}"
github_raw="${DOTFILES_GITHUB_RAW:-https://raw.githubusercontent.com}"
kde_store_api="${DOTFILES_KDE_STORE_API:-https://api.kde-look.org/ocs/v1}"

addons=(krohnkite geometry_change active_accent_frame kde_control_station)

log()  { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

fetch() {
  local url="$1"
  shift
  if [ -n "${GITHUB_TOKEN:-}" ] && [[ "$url" == "$github_api"/* ]]; then
    curl -fsSL --max-time 60 --retry 3 --retry-delay 2 --retry-all-errors -H "Authorization: Bearer $GITHUB_TOKEN" "$@" "$url"
  else
    curl -fsSL --max-time 60 --retry 3 --retry-delay 2 --retry-all-errors "$@" "$url"
  fi
}

json_strings() {
  grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed 's/^"[^"]*"[[:space:]]*:[[:space:]]*"//; s/"$//; s#\\/#/#g'
}

json_field() {
  json_strings "$1" | head -n 1
}

release_tag() {
  local tag
  tag="$(curl -fsSLI --max-time 60 --retry 3 --retry-delay 2 -o /dev/null -w '%{url_effective}' "$github_web/$1/releases/latest" 2>/dev/null | sed -n 's#.*/releases/tag/##p')"
  [ -n "$tag" ] || tag="$(fetch "$github_api/repos/$1/releases/latest" | json_field tag_name)"
  printf '%s' "$tag" | sed 's/^v//'
}

download_release_asset() {
  local repo="$1" tag="$2" name="$3" target="$4" url
  if fetch "$github_web/$repo/releases/download/$tag/$name" -o "$target" 2>/dev/null; then
    return 0
  fi
  url="$(release_asset_url "$repo" "/$name\$")"
  [ -n "$url" ] || url="$(release_asset_url "$repo" "$5")"
  [ -n "$url" ] || die "no $name asset in the latest $repo release"
  fetch "$url" -o "$target"
}

release_asset_url() {
  fetch "$github_api/repos/$1/releases/latest" | json_strings browser_download_url | grep -E "$2" | head -n 1
}

extract() {
  tar -xf "$1" -C "$2" --warning=no-unknown-keyword
}

kpackagetool_bin() {
  if have kpackagetool6; then printf 'kpackagetool6'
  elif have kpackagetool5; then printf 'kpackagetool5'
  else return 1
  fi
}

package_dir_of() {
  local source="$1" unpacked
  if [ -d "$source" ]; then
    printf '%s' "$source"
    return 0
  fi
  have unzip || die "unzip is required to unpack $(basename "$source") without kpackagetool6"
  unpacked="$workdir/unzipped-$(basename "$source")"
  rm -rf "$unpacked"
  mkdir -p "$unpacked"
  unzip -q -o "$source" -d "$unpacked"
  find "$unpacked" -name metadata.json -print -quit | xargs -r dirname
}

kpackage_install() {
  local type="$1" installed_dir="$2" source="$3" tool output package
  if tool="$(kpackagetool_bin)"; then
    if [ -d "$installed_dir" ]; then
      output="$("$tool" --type="$type" --upgrade "$source" 2>&1)" || warn "$tool --upgrade failed: $output"
    else
      output="$("$tool" --type="$type" --install "$source" 2>&1)" || warn "$tool --install failed: $output"
    fi
  else
    warn "kpackagetool6 is not installed; copying the package into place instead"
  fi
  if [ ! -f "$installed_dir/metadata.json" ]; then
    package="$(package_dir_of "$source")"
    [ -n "$package" ] && [ -f "$package/metadata.json" ] || die "no package with metadata.json found in $(basename "$source")"
    mkdir -p "$(dirname "$installed_dir")"
    rm -rf "$installed_dir"
    cp -R "$package" "$installed_dir"
  fi
  [ -f "$installed_dir/metadata.json" ] || die "$type package was not installed at $installed_dir"
}

krohnkite_dir="$data_home/kwin/scripts/krohnkite"
krohnkite_installed() { [ -f "$krohnkite_dir/metadata.json" ] && json_field Version <"$krohnkite_dir/metadata.json"; }
krohnkite_latest()    { release_tag anametologin/krohnkite; }
krohnkite_install() {
  local tag tmp="$workdir/krohnkite"
  tag="$(release_tag anametologin/krohnkite)"
  mkdir -p "$tmp"
  download_release_asset anametologin/krohnkite "$tag" krohnkite.kwinscript "$tmp/krohnkite.kwinscript" '\.kwinscript$'
  kpackage_install KWin/Script "$krohnkite_dir" "$tmp/krohnkite.kwinscript"
}

geometry_change_dir="$data_home/kwin/effects/kwin4_effect_geometry_change"
geometry_change_installed() { [ -f "$geometry_change_dir/metadata.json" ] && json_field Version <"$geometry_change_dir/metadata.json"; }
geometry_change_latest()    { release_tag peterfajdiga/kwin4_effect_geometry_change; }
geometry_change_install() {
  local tag package tmp="$workdir/geometry_change"
  tag="$(release_tag peterfajdiga/kwin4_effect_geometry_change)"
  mkdir -p "$tmp"
  download_release_asset peterfajdiga/kwin4_effect_geometry_change "v$tag" "kwin4_effect_geometry_change_${tag//./_}.tar.gz" "$tmp/effect.tar.gz" '\.tar\.gz$'
  mkdir -p "$tmp/unpacked"
  extract "$tmp/effect.tar.gz" "$tmp/unpacked"
  package="$(find "$tmp/unpacked" -name metadata.json -print -quit | xargs -r dirname)"
  [ -n "$package" ] || die "the kwin4_effect_geometry_change archive has no metadata.json"
  kpackage_install KWin/Effect "$geometry_change_dir" "$package"
}

active_accent_frame_dir="$data_home/aurorae/themes/ActiveAccentFrame"
desktop_field() { sed -n "s/^$1=//p" | head -n 1; }
active_accent_frame_installed() { [ -f "$active_accent_frame_dir/metadata.desktop" ] && desktop_field X-KDE-PluginInfo-Version <"$active_accent_frame_dir/metadata.desktop"; }
active_accent_frame_latest() {
  fetch "$github_raw/nclarius/Plasma-window-decorations/HEAD/ActiveAccentFrame/metadata.desktop" | desktop_field X-KDE-PluginInfo-Version
}
active_accent_frame_install() {
  local theme tmp="$workdir/active_accent_frame"
  mkdir -p "$tmp"
  fetch "$github_web/nclarius/Plasma-window-decorations/archive/HEAD.tar.gz" -o "$tmp/decorations.tar.gz"
  mkdir -p "$tmp/unpacked"
  extract "$tmp/decorations.tar.gz" "$tmp/unpacked"
  theme="$(find "$tmp/unpacked" -type d -name ActiveAccentFrame -print -quit)"
  [ -n "$theme" ] || die "the Plasma-window-decorations archive has no ActiveAccentFrame directory"
  mkdir -p "$(dirname "$active_accent_frame_dir")"
  rm -rf "$active_accent_frame_dir"
  cp -R "$theme" "$active_accent_frame_dir"
}

kde_control_station_dir="$data_home/plasma/plasmoids/KdeControlStation"
kde_control_station_marker="$kde_control_station_dir/.store-version"
kde_control_station_store() { fetch "$kde_store_api/content/data/2196105?format=json"; }
kde_control_station_installed() { [ -f "$kde_control_station_dir/metadata.json" ] && [ -f "$kde_control_station_marker" ] && cat "$kde_control_station_marker"; }
kde_control_station_latest()    { kde_control_station_store | json_field download_version1; }
kde_control_station_install() {
  local url version package tmp="$workdir/kde_control_station"
  local listing
  listing="$(kde_control_station_store)"
  url="$(printf '%s' "$listing" | json_field downloadlink1)"
  version="$(printf '%s' "$listing" | json_field download_version1)"
  [ -n "$url" ] || die "no download link for KDE Control Station on the KDE store"
  mkdir -p "$tmp/unpacked"
  fetch "$url" -o "$tmp/KdeControlStation.tar.xz"
  extract "$tmp/KdeControlStation.tar.xz" "$tmp/unpacked"
  package="$(find "$tmp/unpacked" -name metadata.json -print -quit | xargs -r dirname)"
  [ -n "$package" ] || die "the KDE Control Station archive has no metadata.json"
  kpackage_install Plasma/Applet "$kde_control_station_dir" "$package"
  printf '%s\n' "$version" >"$kde_control_station_marker"
}

kwin_call() {
  local path="$1" interface="$2" method="$3" arg="${4-}" tool reply
  for tool in qdbus6 qdbus-qt6 qdbus; do
    if have "$tool"; then
      if [ -n "$arg" ]; then "$tool" org.kde.KWin "$path" "$interface.$method" "$arg" 2>/dev/null; else "$tool" org.kde.KWin "$path" "$interface.$method" 2>/dev/null; fi
      return
    fi
  done
  if have dbus-send; then
    if [ -n "$arg" ]; then
      reply="$(dbus-send --session --print-reply --dest=org.kde.KWin "$path" "$interface.$method" string:"$arg" 2>/dev/null)" || return 1
    else
      reply="$(dbus-send --session --print-reply --dest=org.kde.KWin "$path" "$interface.$method" 2>/dev/null)" || return 1
    fi
    printf '%s\n' "$reply" | sed -n '2,$p' | sed 's/^[[:space:]]*[a-z]* //; s/^"//; s/"$//'
    return 0
  fi
  if have gdbus; then
    if [ -n "$arg" ]; then
      reply="$(gdbus call --session --dest org.kde.KWin --object-path "$path" --method "$interface.$method" "'$arg'" 2>/dev/null)" || return 1
    else
      reply="$(gdbus call --session --dest org.kde.KWin --object-path "$path" --method "$interface.$method" 2>/dev/null)" || return 1
    fi
    printf '%s\n' "$reply" | sed "s/^(//; s/,)\$//; s/^'//; s/'\$//"
    return 0
  fi
  return 1
}

kwin_reachable() {
  kwin_call /KWin org.kde.KWin supportInformation >/dev/null 2>&1
}

reconfigure_kwin() {
  kwin_call /KWin org.kde.KWin reconfigure >/dev/null 2>&1 || true
}

kwin_effect_loaded() {
  [ "$(kwin_call /Effects org.kde.kwin.Effects isEffectLoaded "$1" 2>/dev/null)" = true ]
}

kwin_load_effect() {
  kwin_call /Effects org.kde.kwin.Effects loadEffect "$1" >/dev/null 2>&1 || true
}

kwin_effect_known() {
  kwin_call /Effects org.kde.kwin.Effects listOfEffects 2>/dev/null | tr ',' '\n' | grep -qx "$1"
}

kwin_compositing_type() {
  kwin_call /KWin org.kde.KWin supportInformation 2>/dev/null | sed -n 's/^Compositing Type:[[:space:]]*//p' | head -n 1
}

kwin_renderer() {
  kwin_call /KWin org.kde.KWin supportInformation 2>/dev/null | sed -n 's/^OpenGL renderer string:[[:space:]]*//p' | head -n 1
}

software_renderer() {
  case "$(kwin_renderer)" in
    *llvmpipe*|*softpipe*|*swrast*|*"Software Rasterizer"*|*SWR*) return 0 ;;
    *) return 1 ;;
  esac
}

force_animations_file="${XDG_CONFIG_HOME:-$HOME/.config}/environment.d/50-kwin-force-animations.conf"

pretty_path() {
  case "$1" in
    "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
    *) printf '%s' "$1" ;;
  esac
}

force_animations_enabled() {
  [ -f "$force_animations_file" ] && grep -qx 'KWIN_EFFECTS_FORCE_ANIMATIONS=1' "$force_animations_file"
}

enable_force_animations() {
  if force_animations_enabled; then
    log "KWIN_EFFECTS_FORCE_ANIMATIONS=1 is already set in $(pretty_path "$force_animations_file"); log out and back in for KWin to pick it up"
    return 0
  fi
  mkdir -p "$(dirname "$force_animations_file")"
  printf 'KWIN_EFFECTS_FORCE_ANIMATIONS=1\n' >"$force_animations_file"
  log "wrote KWIN_EFFECTS_FORCE_ANIMATIONS=1 to $(pretty_path "$force_animations_file"); log out and back in for KWin to load animated effects on this software renderer"
}

explain_effect_not_loaded() {
  local effect="$1" compositing
  compositing="$(kwin_compositing_type)"
  if ! kwin_effect_known "$effect"; then
    warn "$effect: installed under ~/.local/share/kwin/effects but the running KWin does not list it; log out and back in so KWin rescans its effect packages"
    return 0
  fi
  if software_renderer; then
    warn "$effect: KWin lists it but refuses to load animated effects on the software renderer '$(kwin_renderer)' (no GPU acceleration; in a VM enable 3D acceleration)"
    enable_force_animations
    return 0
  fi
  case "$compositing" in
    QPainter|None|"")
      warn "$effect: KWin lists it but refuses to load it because compositing is '${compositing:-unknown}' (software rendering); animated effects need OpenGL. Enable 3D acceleration for this machine or VM and install the GPU driver, then log out and back in"
      ;;
    *)
      warn "$effect: KWin lists it but could not load it while compositing with $compositing; log out and back in, then check System Settings > Desktop Effects and 'journalctl --user -b | grep -i $effect'"
      ;;
  esac
}

geometry_change_activate() {
  kwin_reachable || return 0
  if kwin_effect_loaded kwin4_effect_geometry_change; then
    log "geometry_change: loaded by KWin"
    return 0
  fi
  kwin_load_effect kwin4_effect_geometry_change
  if kwin_effect_loaded kwin4_effect_geometry_change; then
    log "geometry_change: loaded into the running KWin"
  else
    explain_effect_not_loaded kwin4_effect_geometry_change
  fi
}

status_line() {
  local addon="$1" installed="$2" latest="$3"
  if [ -z "$installed" ]; then
    printf '%s: missing (latest %s)\n' "$addon" "$latest"
  elif [ "$installed" != "$latest" ]; then
    printf '%s: update available (%s -> %s)\n' "$addon" "$installed" "$latest"
  else
    printf '%s: up to date (%s)\n' "$addon" "$installed"
  fi
}

run_check() {
  local addon installed latest outdated=0
  for addon in "${addons[@]}"; do
    installed="$("${addon}_installed" || true)"
    latest="$("${addon}_latest" 2>/dev/null || true)"
    if [ -z "$latest" ]; then
      warn "$addon: could not determine the latest upstream version"
      outdated=$((outdated + 1))
      continue
    fi
    status_line "$addon" "$installed" "$latest"
    [ "$installed" = "$latest" ] || outdated=$((outdated + 1))
  done
  if [ -n "$(geometry_change_installed || true)" ] && kwin_reachable; then
    if kwin_effect_loaded kwin4_effect_geometry_change; then
      log "geometry_change: loaded by KWin"
    else
      log "geometry_change: installed but not loaded by KWin (compositing: $(kwin_compositing_type))"
      explain_effect_not_loaded kwin4_effect_geometry_change
    fi
  fi
  [ "$outdated" -eq 0 ]
}

run_install_one() {
  local addon="$1" installed latest
  installed="$("${addon}_installed" || true)"
  latest="$("${addon}_latest")"
  [ -n "$latest" ] || die "$addon: could not determine the latest upstream version"
  if [ "$installed" = "$latest" ]; then
    log "$addon: unchanged ($installed)"
    exit 0
  fi
  "${addon}_install"
  local now
  now="$("${addon}_installed" || true)"
  [ "$now" = "$latest" ] || die "$addon: install finished but version '${now:-none}' is on disk instead of $latest"
  if [ -z "$installed" ]; then
    log "$addon: installed $latest"
  else
    log "$addon: updated $installed -> $latest"
  fi
  exit 3
}

run_install() {
  local addon changed=0 failed=0 rc
  for addon in "${addons[@]}"; do
    rc=0
    "${BASH_SOURCE[0]}" install-one "$addon" || rc=$?
    case "$rc" in
      0) ;;
      3) changed=$((changed + 1)) ;;
      *) warn "$addon: install failed, continuing with the remaining add-ons"; failed=$((failed + 1)) ;;
    esac
  done
  if [ "$changed" -gt 0 ]; then
    reconfigure_kwin
    log "$changed add-on(s) changed"
  else
    log "all add-ons up to date"
  fi
  if [ -n "$(geometry_change_installed || true)" ]; then
    geometry_change_activate
  fi
  [ "$failed" -eq 0 ] || die "$failed add-on(s) failed to install"
}

case "${1:-}" in
  check)   run_check ;;
  install) run_install ;;
  install-one) run_install_one "$2" ;;
  list)    run_check || true ;;
  *)
    printf 'usage: %s check|install|list\n' "$(basename "$0")" >&2
    exit 2
    ;;
esac
