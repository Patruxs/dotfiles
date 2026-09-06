#!/usr/bin/env bash
set -euo pipefail

data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
github_api="${DOTFILES_GITHUB_API:-https://api.github.com}"

font_name="JetBrainsMono Nerd Font"
font_asset="JetBrainsMono.tar.xz"
font_dir="$data_home/fonts/JetBrainsMonoNerdFont"
font_marker="$font_dir/.version"

log()  { printf '%s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

fetch() {
  local url="$1"
  shift
  if [ -n "${GITHUB_TOKEN:-}" ] && [[ "$url" == "$github_api"/* ]]; then
    curl -fsSL --max-time 120 --retry 3 --retry-delay 2 --retry-all-errors -H "Authorization: Bearer $GITHUB_TOKEN" "$@" "$url"
  else
    curl -fsSL --max-time 120 --retry 3 --retry-delay 2 --retry-all-errors "$@" "$url"
  fi
}

json_strings() {
  grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed 's/^"[^"]*"[[:space:]]*:[[:space:]]*"//; s/"$//; s#\\/#/#g'
}

release() {
  fetch "$github_api/repos/ryanoasis/nerd-fonts/releases/latest"
}

system_copy() {
  have fc-list || return 1
  fc-list : family file 2>/dev/null | grep -F "$font_name" | grep -v -F "$data_home/" | grep -q .
}

installed_version() {
  if system_copy; then
    printf 'system'
  elif [ -f "$font_marker" ] && [ -n "$(find "$font_dir" -maxdepth 1 -name '*.ttf' -print -quit)" ]; then
    cat "$font_marker"
  fi
}

latest_version() {
  release | json_strings tag_name | head -n 1 | sed 's/^v//'
}

install_font() {
  local listing url version
  listing="$(release)"
  version="$(printf '%s' "$listing" | json_strings tag_name | head -n 1 | sed 's/^v//')"
  url="$(printf '%s' "$listing" | json_strings browser_download_url | grep -F "/$font_asset" | head -n 1)"
  [ -n "$url" ] || die "no $font_asset asset in the latest nerd-fonts release"
  mkdir -p "$workdir/unpacked"
  fetch "$url" -o "$workdir/$font_asset"
  tar -xf "$workdir/$font_asset" -C "$workdir/unpacked" --warning=no-unknown-keyword
  [ -n "$(find "$workdir/unpacked" -name '*.ttf' -print -quit)" ] || die "the $font_asset archive contains no .ttf files"
  mkdir -p "$(dirname "$font_dir")"
  rm -rf "$font_dir"
  mkdir -p "$font_dir"
  find "$workdir/unpacked" -name '*.ttf' -exec mv {} "$font_dir"/ \;
  printf '%s\n' "$version" >"$font_marker"
  if have fc-cache; then
    fc-cache -f "$font_dir" >/dev/null 2>&1 || true
  fi
}

run_check() {
  local installed latest
  installed="$(installed_version)"
  if [ "$installed" = system ]; then
    log "$font_name: up to date (system package)"
    return 0
  fi
  latest="$(latest_version)"
  [ -n "$latest" ] || die "could not determine the latest nerd-fonts release"
  if [ -z "$installed" ]; then
    log "$font_name: missing (latest $latest)"
    return 1
  elif [ "$installed" != "$latest" ]; then
    log "$font_name: update available ($installed -> $latest)"
    return 1
  fi
  log "$font_name: up to date ($installed)"
}

run_install() {
  local installed latest
  installed="$(installed_version)"
  if [ "$installed" = system ]; then
    log "$font_name: unchanged (system package)"
    return 0
  fi
  latest="$(latest_version)"
  [ -n "$latest" ] || die "could not determine the latest nerd-fonts release"
  if [ "$installed" = "$latest" ]; then
    log "$font_name: unchanged ($installed)"
    return 0
  fi
  install_font
  if [ -z "$installed" ]; then
    log "$font_name: installed $latest"
  else
    log "$font_name: updated $installed -> $latest"
  fi
}

case "${1:-}" in
  check)   run_check ;;
  install) run_install ;;
  *)
    printf 'usage: %s check|install\n' "$(basename "$0")" >&2
    exit 2
    ;;
esac
