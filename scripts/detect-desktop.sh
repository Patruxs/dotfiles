#!/usr/bin/env bash
#
# Detect the desktop environment whose configuration setup should apply.
#
#   gnome   a GNOME session (GNOME Shell, GNOME Classic, GNOME Flashback)
#   kde     a KDE Plasma session
#   other   a desktop this repository has no configuration for
#   none    no desktop at all (server, container, CI runner, SSH into a box
#           with no session running)
#
# Prints the identifier on stdout. With --explain, prints the identifier on
# the first line and the evidence it was based on (one line) on the second,
# so callers can say what the decision was based on.
#
# DOTFILES_DESKTOP=gnome|kde|none overrides detection, for a machine that has
# several desktops installed and no session running (over SSH, for example).
#
# Evidence, strongest first:
#   1. DOTFILES_DESKTOP
#   2. the running session: XDG_CURRENT_DESKTOP, XDG_SESSION_DESKTOP,
#      DESKTOP_SESSION, KDE_FULL_SESSION
#   3. session processes owned by this user: gnome-shell, plasmashell,
#      kwin_wayland, kwin_x11
#   4. the installed session files when nothing is running:
#      /usr/share/wayland-sessions and /usr/share/xsessions
#
# Both bootstrap.sh and the Ansible playbooks call this script, in the same
# environment, so the two always agree. The functions below are sourced by
# test/desktop_detection.sh, which overrides the process and filesystem probes.
set -euo pipefail

detect_desktop_os="$(uname -s)"
desktop_session_dirs=(/usr/share/wayland-sessions /usr/share/xsessions)

# Classify one session name: an XDG_CURRENT_DESKTOP entry, a DESKTOP_SESSION
# value (possibly a full path to a .desktop file), or a session file name.
# Prints gnome, kde, other (a desktop known not to be GNOME or KDE Plasma,
# even when it lists GNOME for compatibility, as Budgie does), or nothing
# when the name says nothing either way (Ubuntu's "ubuntu", Pop!_OS's "pop").
classify_desktop_name() {
  local name="$1"

  name="${name##*/}"
  name="${name%.desktop}"
  name="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"

  case "$name" in
    gnome|gnome-*)
      printf '%s\n' "gnome"
      ;;
    kde|kde-*|plasma|plasma-*|plasmawayland|plasmax11)
      printf '%s\n' "kde"
      ;;
    budgie|budgie-*|cinnamon|x-cinnamon|cosmic|cosmic-*|deepin|enlightenment|hyprland|i3|lxde|lxqt|mate|niri|pantheon|sway|ukui|unity|unity-*|wayfire|xfce|xfce-*)
      printf '%s\n' "other"
      ;;
    *)
      printf '%s\n' ""
      ;;
  esac
}

# Classify a colon-separated list such as "ubuntu:GNOME", "Budgie:GNOME" or
# "KDE". The first entry that says anything wins, so Budgie stays "other"
# even though it lists GNOME after itself. Prints nothing when no entry is
# telling ("ubuntu" on its own).
classify_desktop_list() {
  local list="$1" entry result
  local -a entries=()

  IFS=':' read -r -a entries <<<"$list"
  for entry in "${entries[@]}"; do
    [ -n "$entry" ] || continue
    result="$(classify_desktop_name "$entry")"
    if [ -n "$result" ]; then
      printf '%s\n' "$result"
      return 0
    fi
  done

  printf '%s\n' ""
}

# Classify an installed session file. Distros name these after themselves
# (Ubuntu's ubuntu.desktop and Pop!_OS's pop.desktop are GNOME sessions), so
# the DesktopNames entry inside the file is read first, then the command it
# starts, and only then the file name.
classify_session_file() {
  local file="$1" names exec_line result

  names="$(sed -n 's/^DesktopNames=//p' "$file" 2>/dev/null | head -n 1 | tr -d ';')"
  if [ -n "$names" ]; then
    result="$(classify_desktop_list "$names")"
    if [ -n "$result" ]; then
      printf '%s\n' "$result"
      return 0
    fi
  fi

  exec_line="$(sed -n 's/^Exec=//p' "$file" 2>/dev/null | head -n 1)"
  case "${exec_line##*/}" in
    gnome-session*)
      printf '%s\n' "gnome"
      return 0
      ;;
    startplasma*|startkde*|plasma-dbus-run-session-if-needed*)
      printf '%s\n' "kde"
      return 0
      ;;
  esac

  result="$(classify_desktop_name "$file")"
  printf '%s\n' "${result:-other}"
}

# Whether a process with this exact name runs under the current user. Scoped
# to the user so another account's session on a shared machine is ignored.
session_process_running() {
  pgrep -u "$(id -u)" -x "$1" >/dev/null 2>&1
}

# "other" is accepted as well as the documented gnome|kde|none, so that a
# value this script printed can always be fed back in.
detect_from_override() {
  local override="${DOTFILES_DESKTOP:-}"

  [ -n "$override" ] || return 1

  case "$override" in
    gnome|kde|none|other)
      printf '%s\t%s\n' "$override" "DOTFILES_DESKTOP=$override"
      ;;
    *)
      echo "Unsupported DOTFILES_DESKTOP value: $override (use gnome, kde, or none)" >&2
      return 2
      ;;
  esac
}

# The variables are read strongest first. The first one that names a desktop
# decides, including a desktop known not to be GNOME or KDE; a variable that
# says nothing either way ("ubuntu") defers to the next.
detect_from_session_env() {
  local var value result

  for var in XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP DESKTOP_SESSION; do
    value="${!var:-}"
    [ -n "$value" ] || continue
    result="$(classify_desktop_list "$value")"
    case "$result" in
      gnome|kde)
        printf '%s\t%s\n' "$result" "$var=$value"
        return 0
        ;;
      other)
        printf '%s\t%s\n' "other" "$var=$value is not a GNOME or KDE Plasma session"
        return 0
        ;;
    esac
  done

  if [ "${KDE_FULL_SESSION:-}" = "true" ]; then
    printf '%s\t%s\n' "kde" "KDE_FULL_SESSION=true"
    return 0
  fi

  for var in XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP DESKTOP_SESSION; do
    value="${!var:-}"
    [ -n "$value" ] || continue
    printf '%s\t%s\n' "other" "$var=$value is not a GNOME or KDE Plasma session"
    return 0
  done

  return 1
}

detect_from_processes() {
  local gnome=0 kde=0 process

  if session_process_running gnome-shell; then
    gnome=1
  fi
  for process in plasmashell kwin_wayland kwin_x11; do
    if session_process_running "$process"; then
      kde=1
      break
    fi
  done

  if [ "$gnome" -eq 1 ] && [ "$kde" -eq 1 ]; then
    printf '%s\t%s\n' "other" "both gnome-shell and a Plasma session are running; set DOTFILES_DESKTOP=gnome or DOTFILES_DESKTOP=kde"
    return 0
  fi
  if [ "$gnome" -eq 1 ]; then
    printf '%s\t%s\n' "gnome" "gnome-shell is running"
    return 0
  fi
  if [ "$kde" -eq 1 ]; then
    printf '%s\t%s\n' "kde" "a KDE Plasma session is running"
    return 0
  fi

  return 1
}

detect_from_session_files() {
  local dir file result gnome=0 kde=0 other=0

  for dir in "${desktop_session_dirs[@]}"; do
    [ -d "$dir" ] || continue
    for file in "$dir"/*.desktop; do
      [ -e "$file" ] || continue
      result="$(classify_session_file "$file")"
      case "$result" in
        gnome) gnome=1 ;;
        kde) kde=1 ;;
        other) other=1 ;;
      esac
    done
  done

  if [ "$gnome" -eq 1 ] && [ "$kde" -eq 1 ]; then
    printf '%s\t%s\n' "none" "no desktop session is running and both GNOME and KDE Plasma are installed; set DOTFILES_DESKTOP=gnome or DOTFILES_DESKTOP=kde to choose"
    return 0
  fi
  if [ "$gnome" -eq 1 ]; then
    printf '%s\t%s\n' "gnome" "no desktop session is running; GNOME is the installed desktop"
    return 0
  fi
  if [ "$kde" -eq 1 ]; then
    printf '%s\t%s\n' "kde" "no desktop session is running; KDE Plasma is the installed desktop"
    return 0
  fi
  if [ "$other" -eq 1 ]; then
    printf '%s\t%s\n' "other" "no desktop session is running and the installed desktop is neither GNOME nor KDE Plasma"
    return 0
  fi

  return 1
}

# Prints "<id><TAB><reason>" on one line; main() splits it for --explain.
detect_desktop() {
  local result status=0

  result="$(detect_from_override)" || status=$?
  case "$status" in
    0)
      printf '%s\n' "$result"
      return 0
      ;;
    2)
      return 2
      ;;
  esac

  if [ "$detect_desktop_os" != "Linux" ]; then
    printf '%s\t%s\n' "none" "$detect_desktop_os has no GNOME or KDE Plasma desktop"
    return 0
  fi

  if result="$(detect_from_session_env)"; then
    printf '%s\n' "$result"
    return 0
  fi
  if result="$(detect_from_processes)"; then
    printf '%s\n' "$result"
    return 0
  fi
  if result="$(detect_from_session_files)"; then
    printf '%s\n' "$result"
    return 0
  fi

  printf '%s\t%s\n' "none" "no desktop session is running and no GNOME or KDE Plasma session is installed"
}

usage() {
  cat <<'USAGE'
Usage: detect-desktop.sh [--explain]

Prints gnome, kde, other, or none. With --explain, prints the identifier on
the first line and the evidence it was based on on the second.
DOTFILES_DESKTOP=gnome|kde|none overrides detection.
USAGE
}

main() {
  local explain=0 result

  case "${1:-}" in
    "")
      ;;
    --explain)
      explain=1
      ;;
    -h|--help|help)
      usage
      return 0
      ;;
    *)
      usage >&2
      return 2
      ;;
  esac

  result="$(detect_desktop)" || return "$?"
  if [ "$explain" -eq 1 ]; then
    printf '%s\n%s\n' "${result%%$'\t'*}" "${result#*$'\t'}"
  else
    printf '%s\n' "${result%%$'\t'*}"
  fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
