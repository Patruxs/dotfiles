#!/usr/bin/env bash
# Regression test for scripts/detect-desktop.sh: the desktop environment the
# setup applies configuration for must follow the real session, fall back to
# what is installed when nothing is running, and never guess between two.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DETECTOR="$REPO_ROOT/scripts/detect-desktop.sh"

# shellcheck source=scripts/detect-desktop.sh
source "$DETECTOR"

sessions_dir="$(mktemp -d)"
trap 'rm -rf "$sessions_dir"' EXIT

# Every case starts from a bare environment: no session variables, no
# processes, no installed session files. Each helper then adds one kind of
# evidence.
running_processes=""

session_process_running() {
  case " $running_processes " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

# desktop_session_dirs and detect_desktop_os are read by the sourced detector.
reset_case() {
  unset DOTFILES_DESKTOP XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP DESKTOP_SESSION KDE_FULL_SESSION
  running_processes=""
  rm -rf "${sessions_dir:?}"/*
  mkdir -p "$sessions_dir/wayland-sessions" "$sessions_dir/xsessions"
  # shellcheck disable=SC2034
  desktop_session_dirs=("$sessions_dir/wayland-sessions" "$sessions_dir/xsessions")
  # shellcheck disable=SC2034
  detect_desktop_os="Linux"
}

# install_session <dir> <name> [DesktopNames value] [Exec value]
install_session() {
  {
    echo "[Desktop Entry]"
    echo "Name=$2"
    if [ -n "${3:-}" ]; then echo "DesktopNames=$3"; fi
    if [ -n "${4:-}" ]; then echo "Exec=$4"; fi
  } >"$sessions_dir/$1/$2.desktop"
}

expect() {
  local label="$1" expected="$2" result

  result="$(detect_desktop)" || {
    echo "$label: detection failed"
    exit 1
  }
  if [ "${result%%$'\t'*}" != "$expected" ]; then
    echo "$label: expected '$expected', got '${result%%$'\t'*}' (${result#*$'\t'})"
    exit 1
  fi
  case "$result" in
    *$'\t'?*) ;;
    *)
      echo "$label: expected a reason after the identifier, got '$result'"
      exit 1
      ;;
  esac
}

expect_reason_contains() {
  local label="$1" needle="$2" result

  result="$(detect_desktop)"
  case "${result#*$'\t'}" in
    *"$needle"*) ;;
    *)
      echo "$label: expected the reason to mention '$needle', got '${result#*$'\t'}'"
      exit 1
      ;;
  esac
}

# The override wins over everything and rejects unknown values.
reset_case
export XDG_CURRENT_DESKTOP=KDE DOTFILES_DESKTOP=gnome
expect "override beats the running session" gnome
reset_case
export DOTFILES_DESKTOP=none
running_processes="plasmashell"
expect "override none applies no desktop settings" none
reset_case
export DOTFILES_DESKTOP=cinnamon
if detect_desktop >/dev/null 2>&1; then
  echo "an unsupported DOTFILES_DESKTOP value must be rejected"
  exit 1
fi
# Every value the detector prints must be accepted back, since bootstrap.sh
# and the playbook may hand it over through DOTFILES_DESKTOP.
for value in gnome kde other none; do
  reset_case
  export DOTFILES_DESKTOP="$value"
  expect "round-trip of '$value' through DOTFILES_DESKTOP" "$value"
done

# The running session, from its environment.
reset_case; export XDG_CURRENT_DESKTOP=KDE;                       expect "XDG_CURRENT_DESKTOP=KDE" kde
reset_case; export XDG_CURRENT_DESKTOP=GNOME;                     expect "XDG_CURRENT_DESKTOP=GNOME" gnome
reset_case; export XDG_CURRENT_DESKTOP=ubuntu:GNOME;              expect "Ubuntu's GNOME session" gnome
reset_case; export XDG_CURRENT_DESKTOP=GNOME-Classic:GNOME;       expect "GNOME Classic" gnome
reset_case; export XDG_CURRENT_DESKTOP=GNOME-Flashback:GNOME;     expect "GNOME Flashback" gnome
reset_case; export XDG_CURRENT_DESKTOP=X-Cinnamon;                expect "Cinnamon is another desktop" other
reset_case; export XDG_CURRENT_DESKTOP=Hyprland;                  expect "Hyprland is another desktop" other
reset_case; export XDG_CURRENT_DESKTOP=Unity:Unity7:ubuntu;       expect "Unity is another desktop" other
reset_case; export XDG_CURRENT_DESKTOP=Budgie:GNOME;              expect "Budgie lists GNOME for compatibility but is not GNOME" other
reset_case; export XDG_CURRENT_DESKTOP=Pop:GNOME;                 expect "Pop!_OS's GNOME session" gnome
reset_case; export XDG_CURRENT_DESKTOP=COSMIC;                    expect "COSMIC is another desktop" other
reset_case; export DESKTOP_SESSION=ubuntu;                        expect "an unknown session name alone is other" other
reset_case; export XDG_CURRENT_DESKTOP=X-Cinnamon XDG_SESSION_DESKTOP=KDE; expect "a known other desktop in the strongest variable settles it" other
reset_case; export XDG_CURRENT_DESKTOP=ubuntu XDG_SESSION_DESKTOP=gnome;   expect "an uninformative name defers to the next variable" gnome
reset_case; export XDG_SESSION_DESKTOP=plasma;                    expect "XDG_SESSION_DESKTOP=plasma" kde
reset_case; export DESKTOP_SESSION=/usr/share/wayland-sessions/plasma.desktop; expect "DESKTOP_SESSION as a path" kde
reset_case; export DESKTOP_SESSION=gnome-xorg;                    expect "DESKTOP_SESSION=gnome-xorg" gnome
reset_case; export DESKTOP_SESSION=plasmax11;                     expect "DESKTOP_SESSION=plasmax11" kde
reset_case; export KDE_FULL_SESSION=true;                         expect "KDE_FULL_SESSION=true" kde

# Another desktop's session must not fall through to weaker evidence.
reset_case
export XDG_CURRENT_DESKTOP=XFCE
running_processes="plasmashell"
install_session wayland-sessions gnome
expect "a running non-GNOME/KDE session is other, whatever else is installed" other

# Session processes, for shells with a stripped environment.
reset_case; running_processes="gnome-shell";            expect "gnome-shell process" gnome
reset_case; running_processes="plasmashell";            expect "plasmashell process" kde
reset_case; running_processes="kwin_wayland";           expect "kwin_wayland process" kde
reset_case; running_processes="kwin_x11";               expect "kwin_x11 process" kde
reset_case; running_processes="gnome-shell plasmashell"; expect "two sessions at once is ambiguous" other
expect_reason_contains "two sessions at once" "DOTFILES_DESKTOP"

# Installed session files, when nothing is running (setup over SSH).
reset_case; install_session wayland-sessions plasma;            expect "only Plasma installed" kde
reset_case; install_session xsessions plasmax11;                expect "only Plasma X11 installed" kde
reset_case; install_session wayland-sessions gnome;             expect "only GNOME installed" gnome
reset_case; install_session xsessions gnome-classic;            expect "only GNOME Classic installed" gnome
reset_case; install_session xsessions xfce;                     expect "only another desktop installed" other
reset_case; install_session xsessions ubuntu "ubuntu:GNOME" "env GNOME_SHELL_SESSION_MODE=ubuntu /usr/bin/gnome-session --session=ubuntu"; expect "Ubuntu's ubuntu.desktop is a GNOME session" gnome
reset_case; install_session wayland-sessions pop "pop:GNOME" "/usr/bin/gnome-session --session=pop"; expect "Pop!_OS's pop.desktop is a GNOME session" gnome
reset_case; install_session wayland-sessions plasma "KDE" "/usr/libexec/plasma-dbus-run-session-if-needed /usr/bin/startplasma-wayland"; expect "Plasma's session file by its DesktopNames" kde
reset_case; install_session xsessions custom "" "/usr/bin/startplasma-x11"; expect "a renamed Plasma session by its Exec" kde
reset_case; install_session xsessions budgie-desktop "Budgie:GNOME" "/usr/bin/budgie-desktop"; expect "Budgie's session file is another desktop" other
reset_case
install_session wayland-sessions plasma
install_session wayland-sessions gnome
expect "GNOME and Plasma both installed, nothing running" none
expect_reason_contains "both installed" "DOTFILES_DESKTOP"

# Headless: nothing at all.
reset_case; expect "no session, no processes, no session files" none

# Not Linux.
reset_case
# shellcheck disable=SC2034
detect_desktop_os="Darwin"
running_processes="plasmashell"
expect "macOS never has desktop settings" none

# The command-line contract used by bootstrap.sh and the playbooks.
reset_case
output="$(env -i PATH="$PATH" XDG_CURRENT_DESKTOP=KDE bash "$DETECTOR")"
if [ "$output" != "kde" ]; then
  echo "expected the plain form to print only the identifier, got '$output'"
  exit 1
fi
output="$(env -i PATH="$PATH" XDG_CURRENT_DESKTOP=KDE bash "$DETECTOR" --explain)"
if [ "$(printf '%s\n' "$output" | sed -n 1p)" != "kde" ] || [ "$(printf '%s\n' "$output" | sed -n 2p)" != "XDG_CURRENT_DESKTOP=KDE" ]; then
  echo "expected --explain to print the identifier then the reason, got '$output'"
  exit 1
fi
if env -i PATH="$PATH" DOTFILES_DESKTOP=bogus bash "$DETECTOR" >/dev/null 2>&1; then
  echo "expected an invalid DOTFILES_DESKTOP to make the script fail"
  exit 1
fi

echo "desktop detection passed"
