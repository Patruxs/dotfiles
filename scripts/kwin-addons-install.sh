#!/usr/bin/env bash
set -euo pipefail

data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
github_api="${DOTFILES_GITHUB_API:-https://api.github.com}"
github_web="${DOTFILES_GITHUB_WEB:-https://github.com}"
github_raw="${DOTFILES_GITHUB_RAW:-https://raw.githubusercontent.com}"

addons=(krohnkite geometry_change active_accent_frame)

log()  { printf '%s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

fetch() {
  local url="$1"
  shift
  if [ -n "${GITHUB_TOKEN:-}" ] && [[ "$url" == "$github_api"/* ]]; then
    curl -fsSL --max-time 60 -H "Authorization: Bearer $GITHUB_TOKEN" "$@" "$url"
  else
    curl -fsSL --max-time 60 "$@" "$url"
  fi
}

json_field() {
  sed -n "s/^[[:space:]]*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n 1
}

release_tag() {
  fetch "$github_api/repos/$1/releases/latest" | json_field tag_name | sed 's/^v//'
}

release_asset_url() {
  fetch "$github_api/repos/$1/releases/latest" \
    | sed -n 's/^[[:space:]]*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | grep -E "$2" | head -n 1
}

kpackagetool_bin() {
  if have kpackagetool6; then printf 'kpackagetool6'
  elif have kpackagetool5; then printf 'kpackagetool5'
  else return 1
  fi
}

kpackage_install() {
  local type="$1" installed_dir="$2" source="$3" tool
  tool="$(kpackagetool_bin)" || die "kpackagetool6 is not installed; install the KDE package tools (kpackage)"
  if [ -d "$installed_dir" ]; then
    "$tool" --type="$type" --upgrade "$source" >/dev/null
  else
    "$tool" --type="$type" --install "$source" >/dev/null
  fi
}

krohnkite_dir="$data_home/kwin/scripts/krohnkite"
krohnkite_installed() { [ -f "$krohnkite_dir/metadata.json" ] && json_field Version <"$krohnkite_dir/metadata.json"; }
krohnkite_latest()    { release_tag anametologin/krohnkite; }
krohnkite_install() {
  local url tmp="$workdir/krohnkite"
  url="$(release_asset_url anametologin/krohnkite '\.kwinscript$')"
  [ -n "$url" ] || die "no .kwinscript asset in the latest krohnkite release"
  mkdir -p "$tmp"
  fetch "$url" -o "$tmp/krohnkite.kwinscript"
  kpackage_install KWin/Script "$krohnkite_dir" "$tmp/krohnkite.kwinscript"
}

geometry_change_dir="$data_home/kwin/effects/kwin4_effect_geometry_change"
geometry_change_installed() { [ -f "$geometry_change_dir/metadata.json" ] && json_field Version <"$geometry_change_dir/metadata.json"; }
geometry_change_latest()    { release_tag peterfajdiga/kwin4_effect_geometry_change; }
geometry_change_install() {
  local url package tmp="$workdir/geometry_change"
  url="$(release_asset_url peterfajdiga/kwin4_effect_geometry_change '\.tar\.gz$')"
  [ -n "$url" ] || die "no .tar.gz asset in the latest kwin4_effect_geometry_change release"
  mkdir -p "$tmp"
  fetch "$url" -o "$tmp/effect.tar.gz"
  mkdir -p "$tmp/unpacked"
  tar -xzf "$tmp/effect.tar.gz" -C "$tmp/unpacked"
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
  tar -xzf "$tmp/decorations.tar.gz" -C "$tmp/unpacked"
  theme="$(find "$tmp/unpacked" -type d -name ActiveAccentFrame -print -quit)"
  [ -n "$theme" ] || die "the Plasma-window-decorations archive has no ActiveAccentFrame directory"
  mkdir -p "$(dirname "$active_accent_frame_dir")"
  rm -rf "$active_accent_frame_dir"
  cp -R "$theme" "$active_accent_frame_dir"
}

reconfigure_kwin() {
  [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] || return 0
  if have qdbus6; then
    qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
  elif have qdbus; then
    qdbus org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
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
    latest="$("${addon}_latest")"
    [ -n "$latest" ] || die "could not determine the latest version of $addon"
    status_line "$addon" "$installed" "$latest"
    [ "$installed" = "$latest" ] || outdated=$((outdated + 1))
  done
  [ "$outdated" -eq 0 ]
}

run_install() {
  local addon installed latest changed=0
  for addon in "${addons[@]}"; do
    installed="$("${addon}_installed" || true)"
    latest="$("${addon}_latest")"
    [ -n "$latest" ] || die "could not determine the latest version of $addon"
    if [ "$installed" = "$latest" ]; then
      log "$addon: unchanged ($installed)"
      continue
    fi
    "${addon}_install"
    if [ -z "$installed" ]; then
      log "$addon: installed $latest"
    else
      log "$addon: updated $installed -> $latest"
    fi
    changed=$((changed + 1))
  done
  if [ "$changed" -gt 0 ]; then
    reconfigure_kwin
    log "$changed add-on(s) changed"
  else
    log "all add-ons up to date"
  fi
}

case "${1:-}" in
  check)   run_check ;;
  install) run_install ;;
  list)    run_check || true ;;
  *)
    printf 'usage: %s check|install|list\n' "$(basename "$0")" >&2
    exit 2
    ;;
esac
