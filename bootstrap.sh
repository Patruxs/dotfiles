#!/usr/bin/env bash
# shellcheck disable=SC2329  # setup steps are invoked indirectly through run_step and the EXIT trap
set -euo pipefail

repo="${DOTFILES_REPO:-}"
script_source="${BASH_SOURCE[0]:-}"
script_dir=""
if [ -n "$script_source" ]; then
  script_dir="$(cd "$(dirname "$script_source")" && pwd)"
fi
chezmoi_dir="$HOME/.local/share/chezmoi"
OS="$(uname -s)"
DISTRO=""
platform=""
setup_mode="${DOTFILES_SETUP_MODE:-best_effort}"
report_file="$HOME/.dotfiles_setup_report.md"

if [ "$OS" = "Linux" ] && [ -f /etc/os-release ]; then
  # shellcheck disable=SC1091  # system file, not part of this repo
  . /etc/os-release
  DISTRO="$ID"
fi

have() {
  command -v "$1" >/dev/null 2>&1
}

is_ci() {
  case "${DOTFILES_CI:-}" in
    1|true|TRUE|yes|YES)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

using_checked_out_source() {
  [ -n "$script_dir" ] &&
    [ -e "$script_dir/.git" ] &&
    [ -f "$script_dir/ansible/playbooks/setup.yml" ]
}

resolve_chezmoi_dir() {
  if using_checked_out_source; then
    chezmoi_dir="$script_dir"
  fi
}

print_banner() {
  cat <<'EOF'
▓▓▓▓   ▓▓▓  ▓▓▓▓▓ ▓▓▓▓▓ ▓▓▓ ▓     ▓▓▓▓▓  ▓▓▓▓
▓   ▓ ▓   ▓   ▓   ▓      ▓  ▓     ▓     ▓
▓   ▓ ▓   ▓   ▓   ▓▓▓▓   ▓  ▓     ▓▓▓▓   ▓▓▓
▓   ▓ ▓   ▓   ▓   ▓      ▓  ▓     ▓         ▓
▓▓▓▓   ▓▓▓    ▓   ▓     ▓▓▓ ▓▓▓▓▓ ▓▓▓▓▓ ▓▓▓▓
EOF
}

has_interactive_tty() {
  [ -t 0 ] || [ -t 1 ] || [ -t 2 ]
}

show_welcome_screen() {
  local tty_device

  if has_interactive_tty && [ -r /dev/tty ] && [ -w /dev/tty ]; then
    tty_device="/dev/tty"
    if have clear; then
      clear >"$tty_device" 2>/dev/null || printf '\033c' >"$tty_device"
    else
      printf '\033c' >"$tty_device"
    fi
    print_banner >"$tty_device"
  else
    print_banner
  fi
}

sudo_password=""
become_password_file=""

require_tty_device() {
  if [ -r /dev/tty ] && [ -w /dev/tty ]; then
    printf '%s\n' "/dev/tty"
    return 0
  fi

  echo "An interactive terminal is required for this setup."
  exit 1
}

cleanup_sensitive_state() {
  unset ANSIBLE_BECOME_PASS ANSIBLE_SUDO_PASS ANSIBLE_BECOME_FLAGS ANSIBLE_SUDO_FLAGS
  sudo_password=""
  if [ -n "$become_password_file" ] && [ -f "$become_password_file" ]; then
    rm -f "$become_password_file"
  fi
  become_password_file=""
}

prompt_sudo_password() {
  local tty_device

  tty_device="$(require_tty_device)"
  printf "Sudo password: " >"$tty_device"
  IFS= read -r -s sudo_password <"$tty_device"
  printf "\n" >"$tty_device"

  if [ -z "$sudo_password" ]; then
    abort "A sudo password is required for setup."
  fi
}

validate_sudo_password() {
  if ! printf '%s\n' "$sudo_password" | sudo -S -k -p '' -v >/dev/null 2>&1; then
    abort "The provided sudo password was not accepted."
  fi
}

have_passwordless_sudo() {
  sudo -k -n true >/dev/null 2>&1
}

ensure_linux_sudo_access() {
  if [ "$OS" != "Linux" ]; then
    return
  fi

  if ! have sudo; then
    abort "sudo is required for Linux setup."
  fi

  if have_passwordless_sudo; then
    return
  fi

  if is_ci; then
    abort "CI Linux setup requires passwordless sudo."
  fi

  prompt_sudo_password
  validate_sudo_password
  create_become_password_file
}

run_privileged() {
  if [ "$OS" != "Linux" ]; then
    "$@"
    return
  fi

  if [ -n "$sudo_password" ]; then
    printf '%s\n' "$sudo_password" | sudo -S -p '' "$@"
    return
  fi

  sudo "$@"
}

create_become_password_file() {
  become_password_file="$(mktemp)"
  chmod 600 "$become_password_file"
  printf '%s\n' "$sudo_password" >"$become_password_file"
}

# ---------------------------------------------------------------------------
# Step outcomes and the setup report.
#
# Every prerequisite step runs through run_step, which records whether it
# succeeded, failed, or was skipped. In best-effort mode a failed step is
# skipped and setup continues; only steps that later phases cannot work
# without (chezmoi, the repository clone, Ansible) stop the run. The collected
# outcomes are handed to Ansible, which merges them into the final Markdown
# report, and if Ansible never runs the EXIT trap writes that report itself so
# a failed run always leaves ~/.dotfiles_setup_report.md behind.
# ---------------------------------------------------------------------------

bootstrap_outcome_status=()
bootstrap_outcome_name=()
bootstrap_outcome_detail=()
bootstrap_failure_count=0
bootstrap_abort_reason=""
bootstrap_outcomes_file=""
ansible_log=""
ansible_exit_code=""
ansible_started=0
report_stamp_file=""
report_written_by_ansible=0

strip_ansi() {
  # BSD sed has no \x1B escape, so splice the literal ESC byte into the pattern.
  # LC_ALL=C keeps BSD sed from rejecting bytes that are not valid UTF-8.
  LC_ALL=C sed -e "s/$(printf '\033')\\[[0-9;]*[A-Za-z]//g"
}

sanitize_captured_output() {
  # Captured step output can carry colour codes and carriage-return progress
  # lines; neither belongs in the report or the JSON handoff.
  strip_ansi | LC_ALL=C tr -d '\r'
}

json_escape() {
  local value

  # Drop control characters JSON cannot carry (tab and newline are escaped
  # below), then escape the rest.
  value="$(printf '%s' "$1" | LC_ALL=C tr -d '\000-\010\013-\037\177')"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\t'/\\t}"
  value="${value//$'\n'/\\n}"
  printf '%s' "$value"
}

abort() {
  # Stop the run with a reason the EXIT trap can put into the report.
  bootstrap_abort_reason="$1"
  echo "$bootstrap_abort_reason"
  exit 1
}

record_outcome() {
  local status="$1"
  local name="$2"
  local detail="${3:-}"

  bootstrap_outcome_status+=("$status")
  bootstrap_outcome_name+=("$name")
  bootstrap_outcome_detail+=("$detail")

  if [ "$status" = "failed" ]; then
    bootstrap_failure_count=$((bootstrap_failure_count + 1))
  fi
}

run_step() {
  # usage: run_step [--critical] "<step name>" command [args...]
  #
  # The command runs in a subshell with errexit enabled, so a multi-command
  # step stops at its first failing command while this shell keeps going. Its
  # output is shown live and captured, so the report can quote the error.
  local critical=0
  local name step_log rc detail headline

  if [ "$1" = "--critical" ]; then
    critical=1
    shift
  fi
  name="$1"
  shift

  step_log="$(mktemp)"
  set +e
  ( set -e; "$@" ) 2>&1 | tee "$step_log"
  rc="${PIPESTATUS[0]}"
  set -e
  hash -r

  if [ "$rc" -eq 0 ]; then
    rm -f "$step_log"
    record_outcome ok "$name"
    return 0
  fi

  detail="$(tail -n 25 "$step_log" | sanitize_captured_output || true)"
  rm -f "$step_log"
  # Lead with the last non-empty output line: for shell tools that is almost
  # always the actual error, and the report's terminal summary shows only the
  # first line of each failure.
  headline="$(printf '%s\n' "$detail" | grep -v '^[[:space:]]*$' | tail -n 1 || true)"
  record_outcome failed "$name" "Exit status ${rc}${headline:+: }${headline}${detail:+

Last output lines:
}${detail}"

  if [ "$critical" -eq 1 ]; then
    bootstrap_abort_reason="'$name' failed and setup cannot continue without it."
    echo "ERROR: $bootstrap_abort_reason"
    exit 1
  fi

  if [ "$setup_mode" = "strict" ]; then
    bootstrap_abort_reason="'$name' failed and strict mode stops at the first failure."
    echo "ERROR: $bootstrap_abort_reason"
    exit 1
  fi

  echo "WARNING: '$name' failed (exit status $rc). Skipping it and continuing in best-effort mode; the error is recorded in the setup report."
  return 0
}

write_bootstrap_outcomes_file() {
  local index

  bootstrap_outcomes_file="$(mktemp)"
  : >"$bootstrap_outcomes_file"
  for index in "${!bootstrap_outcome_status[@]}"; do
    printf '{"status":"%s","name":"%s","detail":"%s"}\n' \
      "$(json_escape "${bootstrap_outcome_status[$index]}")" \
      "$(json_escape "${bootstrap_outcome_name[$index]}")" \
      "$(json_escape "${bootstrap_outcome_detail[$index]}")" \
      >>"$bootstrap_outcomes_file"
  done
}

write_fallback_report() {
  # Only used when Ansible did not write the report itself (a prerequisite
  # step aborted the run, or the playbook failed before its summary ran).
  local exit_status="$1"
  local result index status name detail

  if [ -n "$bootstrap_abort_reason" ]; then
    result="Aborted: $bootstrap_abort_reason"
  elif [ "$ansible_started" -eq 1 ] && [ -n "$ansible_exit_code" ] && [ "$ansible_exit_code" -ne 0 ]; then
    result="Aborted: the Ansible playbook exited with status $ansible_exit_code before it could write its summary."
  elif [ "$exit_status" -ne 0 ]; then
    result="Aborted: bootstrap exited with status $exit_status before Ansible started; the terminal output above has the message."
  elif [ "$bootstrap_failure_count" -gt 0 ]; then
    result="Completed with $bootstrap_failure_count skipped failure(s)."
  else
    result="Completed successfully."
  fi

  {
    echo "# Dotfiles setup report"
    echo
    echo "- Date: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "- Profile: \`${profile:-unknown}\`"
    echo "- Platform: \`${platform:-unknown}\`"
    echo "- Mode: \`$setup_mode\`"
    echo "- Result: $result"
    echo
    echo "## Errors"
    echo
    if [ "$bootstrap_failure_count" -eq 0 ] && { [ "$ansible_started" -eq 0 ] || [ -z "$ansible_exit_code" ] || [ "$ansible_exit_code" -eq 0 ]; }; then
      if [ -n "$bootstrap_abort_reason" ]; then
        echo "### [bootstrap] setup stopped before any step failed"
        echo
        printf '%s\n' "$bootstrap_abort_reason"
      else
        echo "No errors were recorded before the run stopped."
      fi
      echo
    fi
    for index in "${!bootstrap_outcome_status[@]}"; do
      status="${bootstrap_outcome_status[$index]}"
      if [ "$status" != "failed" ]; then
        continue
      fi
      name="${bootstrap_outcome_name[$index]}"
      detail="${bootstrap_outcome_detail[$index]}"
      echo "### [bootstrap] $name"
      echo
      echo '````text'
      printf '%s\n' "$detail" | sanitize_captured_output || true
      echo '````'
      echo
    done
    if [ "$ansible_started" -eq 1 ] && [ -n "$ansible_exit_code" ] && [ "$ansible_exit_code" -ne 0 ]; then
      echo "### [ansible] ansible/playbooks/${platform:-unknown}.yml"
      echo
      echo "The playbook exited with status $ansible_exit_code. Last lines of its output:"
      echo
      echo '````text'
      if [ -n "$ansible_log" ] && [ -f "$ansible_log" ]; then
        tail -n 60 "$ansible_log" | sanitize_captured_output || true
      else
        echo "(no output captured)"
      fi
      echo '````'
      echo
    fi
    echo "## Completed steps"
    echo
    for index in "${!bootstrap_outcome_status[@]}"; do
      status="${bootstrap_outcome_status[$index]}"
      name="${bootstrap_outcome_name[$index]}"
      detail="${bootstrap_outcome_detail[$index]}"
      case "$status" in
        ok)
          echo "- [bootstrap] $name"
          ;;
        skipped)
          echo "- [bootstrap] $name: skipped${detail:+ - }${detail}"
          ;;
      esac
    done
    if [ "${#bootstrap_outcome_status[@]}" -eq 0 ]; then
      echo "- No steps completed."
    fi
    echo
    echo "## Next steps"
    echo
    echo "- Setup is safe to re-run. Fix the cause above, then run \`./bootstrap.sh --profile ${profile:-personal}\` again; completed steps are skipped or no-ops."
    echo "- Use \`--strict\` to stop at the first failure while debugging."
  } >"$report_file"
}

print_report_banner() {
  local result_line=""

  if [ ! -f "$report_file" ]; then
    return
  fi

  result_line="$(grep -m1 '^- Result:' "$report_file" 2>/dev/null | sed 's/^- Result: //')"
  echo
  echo "==========================================================="
  if [ -n "$result_line" ]; then
    echo "Setup result: $result_line"
  else
    echo "Setup finished (or aborted). A full report has been saved."
  fi
  echo "Read your setup outcome summary at: $report_file"
  echo "==========================================================="
}

on_exit() {
  local exit_status=$?

  set +e
  cleanup_sensitive_state

  # Once the trap is armed every exit leaves a report from this run behind, so
  # the banner below never points at a stale report from an earlier run.
  if [ "$report_written_by_ansible" -ne 1 ]; then
    write_fallback_report "$exit_status"
  fi

  print_report_banner

  if [ -n "$bootstrap_outcomes_file" ]; then
    rm -f "$bootstrap_outcomes_file"
  fi
  if [ -n "$ansible_log" ]; then
    rm -f "$ansible_log"
  fi
  if [ -n "$report_stamp_file" ]; then
    rm -f "$report_stamp_file"
  fi

  exit "$exit_status"
}

refresh_repo() {
  if using_checked_out_source; then
    echo "Using checked-out dotfiles repo without refreshing it."
    return
  fi

  if ! have git; then
    return
  fi

  if git -C "$chezmoi_dir" diff --quiet --ignore-submodules HEAD -- 2>/dev/null &&
    git -C "$chezmoi_dir" diff --quiet --ignore-submodules --cached -- 2>/dev/null; then
    echo "Refreshing dotfiles repo..."
    git -C "$chezmoi_dir" pull --ff-only --quiet || {
      echo "Warning: could not fast-forward the existing dotfiles checkout. Continuing with the local copy."
    }
  else
    echo "Skipping dotfiles repo refresh because the local checkout has uncommitted changes."
  fi
}

install_packages() {
  if [ "$OS" = "Darwin" ]; then
    if ! have brew; then
      echo "Homebrew not found. Please install Homebrew first."
      exit 1
    fi
    brew install "$@"
  elif [ "$OS" = "Linux" ]; then
    case "$DISTRO" in
      fedora)
        run_privileged dnf install -y "$@"
        ;;
      debian|ubuntu)
        run_privileged env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
        ;;
      arch|manjaro)
        run_privileged pacman -S --noconfirm --needed "$@"
        ;;
      *)
        echo "Unsupported Linux distro: $DISTRO"
        exit 1
        ;;
    esac
  else
    echo "Unsupported OS: $OS"
    exit 1
  fi
}

repair_broken_docker_desktop() {
  # Docker Desktop installs from a direct .deb, so no apt repository can repair
  # it. If an interrupted install left dpkg demanding a reinstall (reinstreq),
  # every apt transaction aborts with "needs to be reinstalled, but I can't
  # find an archive for it". Remove the broken package; setup reinstalls it.
  if ! have dpkg-query; then
    return
  fi

  if [ "$(dpkg-query -W -f '${db:Status-Eflag}' docker-desktop 2>/dev/null)" != "reinstreq" ]; then
    return
  fi

  echo "Docker Desktop is half-installed and blocks apt. Removing the broken package so setup can reinstall it..."
  run_privileged dpkg --remove --force-remove-reinstreq docker-desktop
}

update_system() {
  echo "Updating system packages before setup..."
  case "$DISTRO" in
    fedora)
      run_privileged dnf upgrade --refresh -y
      ;;
    debian|ubuntu)
      repair_broken_docker_desktop
      run_privileged env DEBIAN_FRONTEND=noninteractive apt-get update
      run_privileged env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y \
        -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold
      ;;
    arch|manjaro)
      run_privileged pacman -Syu --noconfirm
      ;;
    *)
      echo "Unsupported Linux distro: $DISTRO"
      exit 1
      ;;
  esac
}

is_snap_binary() {
  local path="$1"
  local resolved=""

  case "$path" in
    /snap/*|/var/lib/snapd/*)
      return 0
      ;;
  esac

  resolved="$(readlink -f "$path" 2>/dev/null || true)"
  case "$resolved" in
    /snap/*|/var/lib/snapd/*)
      return 0
      ;;
  esac

  return 1
}

curl_is_snap() {
  # The Snap build of curl is strictly confined: it cannot read or write the
  # host /tmp or hidden directories under HOME, so installers that download
  # to a temp file and read it back (chezmoi's get.chezmoi.io script fails
  # with "real_tag error retrieving GitHub release latest") silently break.
  [ "$OS" = "Linux" ] && have curl && is_snap_binary "$(command -v curl)"
}

fetch_to_stdout() {
  if have curl && ! curl_is_snap; then
    curl -fsSL "$1"
  elif have wget; then
    wget -qO- "$1"
  elif have curl; then
    curl -fsSL "$1"
  else
    echo "Neither curl nor wget is available." >&2
    return 1
  fi
}

fetch_to_file() {
  if have curl && ! curl_is_snap; then
    curl -fsSL -o "$2" "$1"
  elif have wget; then
    wget -qO "$2" "$1"
  elif have curl; then
    curl -fsSL -o "$2" "$1"
  else
    echo "Neither curl nor wget is available." >&2
    return 1
  fi
}

ensure_download_tool() {
  if have curl && ! curl_is_snap; then
    return
  fi

  if curl_is_snap; then
    echo "curl resolves to the Snap build at $(command -v curl). Snap confinement hides /tmp and hidden home directories from it, which breaks upstream installers. Installing the native curl package..."
    install_packages curl
    hash -r
    if curl_is_snap; then
      echo "WARNING: curl still resolves to the Snap build. Downloads will prefer wget instead."
      if ! have wget; then
        install_packages wget
      fi
    fi
    return
  fi

  if have wget; then
    return
  fi

  echo "Neither curl nor wget was found. Installing curl..."
  install_packages curl
}

ensure_git() {
  if have git; then
    return
  fi

  echo "Git not found. Installing..."
  install_packages git
}

install_chezmoi_release_binary() {
  # Fallback for when the get.chezmoi.io installer cannot run: fetch the
  # prebuilt binary straight from the latest GitHub release.
  local os arch asset tmp_binary

  case "$OS" in
    Linux)
      os="linux"
      ;;
    Darwin)
      os="darwin"
      ;;
    *)
      return 1
      ;;
  esac

  case "$(uname -m)" in
    x86_64|amd64)
      arch="amd64"
      ;;
    arm64|aarch64)
      arch="arm64"
      ;;
    *)
      echo "No prebuilt chezmoi binary is published for $(uname -m)."
      return 1
      ;;
  esac

  if [ "$os" = "linux" ] && [ "$arch" != "amd64" ]; then
    echo "No prebuilt chezmoi binary is published for Linux $(uname -m)."
    return 1
  fi

  asset="chezmoi-${os}-${arch}"
  tmp_binary="$(mktemp)"
  if ! fetch_to_file "https://github.com/twpayne/chezmoi/releases/latest/download/${asset}" "$tmp_binary"; then
    rm -f "$tmp_binary"
    return 1
  fi
  chmod 0755 "$tmp_binary"
  # Verify before installing: a captive portal or proxy can answer with an HTML
  # page and HTTP 200, and a broken ~/.local/bin/chezmoi would make every
  # re-run skip the install step.
  if ! "$tmp_binary" --version >/dev/null 2>&1; then
    echo "The downloaded chezmoi binary does not run; discarding it."
    rm -f "$tmp_binary"
    return 1
  fi
  mv "$tmp_binary" "$HOME/.local/bin/chezmoi"
}

install_chezmoi_from_package_manager() {
  if [ "$OS" = "Darwin" ]; then
    install_packages chezmoi
    return
  fi

  case "$DISTRO" in
    fedora|arch|manjaro)
      install_packages chezmoi
      ;;
    *)
      echo "No chezmoi package is available from the $DISTRO package manager."
      return 1
      ;;
  esac
}

install_chezmoi() {
  mkdir -p "$HOME/.local/bin"

  if fetch_to_stdout "https://get.chezmoi.io/lb" | sh -s -- -b "$HOME/.local/bin" && [ -x "$HOME/.local/bin/chezmoi" ]; then
    return
  fi

  echo "The chezmoi installer script failed. Trying a direct download of the latest release binary..."
  if install_chezmoi_release_binary; then
    return
  fi

  echo "Trying the system package manager for chezmoi..."
  install_chezmoi_from_package_manager
}

upgrade_chezmoi() {
  chezmoi upgrade
}

init_chezmoi_from_source() {
  echo "Initializing Chezmoi from checked-out source: $chezmoi_dir"
  chezmoi init --source "$chezmoi_dir"
}

init_chezmoi_from_repo() {
  chezmoi init "$repo"
}

install_ansible() {
  echo "Ansible not found. Installing..."
  install_packages ansible
}

detect_platform() {
  case "$OS" in
    Darwin)
      printf '%s\n' "macos"
      ;;
    Linux)
      case "$DISTRO" in
        ubuntu)
          printf '%s\n' "ubuntu"
          ;;
        fedora)
          printf '%s\n' "fedora"
          ;;
        arch|manjaro)
          printf '%s\n' "arch"
          ;;
        *)
          echo "Unsupported Linux distro: $DISTRO" >&2
          return 1
          ;;
      esac
      ;;
    *)
      echo "Unsupported OS: $OS" >&2
      return 1
      ;;
  esac
}

resolve_platform() {
  local detected_platform

  detected_platform="$(detect_platform)" || exit 1

  if [ -z "$platform" ]; then
    platform="$detected_platform"
    return
  fi

  if ! is_ci; then
    echo "--platform is only supported when DOTFILES_CI=1."
    exit 1
  fi

  case "$platform" in
    ubuntu|fedora|arch|macos)
      ;;
    *)
      echo "Unsupported platform override: $platform"
      exit 1
      ;;
  esac
}

required_ansible_collections_present() {
  # Presence check only; the distro ansible bundles ship versions well past the
  # pinned minimums, and a real version conflict still fails loudly in the play.
  local requirements_file collection_name

  requirements_file="$1"

  while IFS= read -r collection_name; do
    if ! ansible-galaxy collection list "$collection_name" 2>/dev/null | grep -q "$collection_name"; then
      return 1
    fi
  done < <(sed -n 's/^[[:space:]]*-[[:space:]]*name:[[:space:]]*//p' "$requirements_file")
}

ansible_collections_requirements_file() {
  printf '%s\n' "$chezmoi_dir/ansible/collections/requirements.yml"
}

refresh_ansible_collections() {
  # Galaxy can be unreachable (outages, flaky networks, regional TLS resets).
  # This step is not critical: a failed refresh is recorded in the report and
  # verify_ansible_collections decides whether the run can continue.
  local requirements_file attempt

  requirements_file="$(ansible_collections_requirements_file)"

  if [ ! -f "$requirements_file" ] || ! have ansible-galaxy; then
    return
  fi

  echo "Installing or updating required Ansible collections..."
  for attempt in 1 2 3; do
    if ansible-galaxy collection install --upgrade -r "$requirements_file"; then
      return
    fi
    if [ "$attempt" -lt 3 ]; then
      echo "Ansible Galaxy did not respond (attempt $attempt of 3). Retrying..."
      sleep 5
    fi
  done

  echo "WARNING: Could not refresh Ansible collections from Galaxy. Continuing with the already-installed versions."
  return 1
}

verify_ansible_collections() {
  # The distro ansible package already bundles community.general, so a failed
  # Galaxy refresh is fine as long as every required collection is installed.
  local requirements_file

  requirements_file="$(ansible_collections_requirements_file)"

  if [ ! -f "$requirements_file" ] || ! have ansible-galaxy; then
    return
  fi

  if required_ansible_collections_present "$requirements_file"; then
    return
  fi

  echo "Could not reach Ansible Galaxy and a required collection is missing. Check network access to galaxy.ansible.com and re-run bootstrap.sh."
  exit 1
}

choose_profile() {
  local tty_device
  local choice

  if [ -n "${DOTFILES_PROFILE:-}" ]; then
    profile="${DOTFILES_PROFILE}"
    return
  fi

  if has_interactive_tty; then
    tty_device="$(require_tty_device)"
  else
    echo "No interactive terminal found."
    echo "Run again with --profile personal, --profile work, or DOTFILES_PROFILE=personal."
    exit 1
  fi

  while true; do
    {
      echo
      echo "Choose your setup profile:"
      echo "  1) personal"
      echo "  2) work"
      printf "Enter choice [1-2]: "
    } >"$tty_device"

    IFS= read -r choice <"$tty_device" || true

    case "$choice" in
      1|personal|Personal|PERSONAL)
        profile="personal"
        return
        ;;
      2|work|Work|WORK)
        profile="work"
        return
        ;;
      *)
        echo "Invalid choice. Please enter 1 or 2." >"$tty_device"
        ;;
    esac
  done
}

profile=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --profile)
      if [[ $# -lt 2 ]]; then
        echo "--profile requires a value."
        exit 1
      fi
      profile="$2"
      shift 2
      ;;
    --platform)
      if [[ $# -lt 2 ]]; then
        echo "--platform requires a value."
        exit 1
      fi
      platform="$2"
      shift 2
      ;;
    --strict)
      setup_mode="strict"
      shift
      ;;
    --best-effort)
      setup_mode="best_effort"
      shift
      ;;
    --help|-h)
      echo "Usage: $0 [--profile personal|work] [--platform ubuntu|fedora|arch|macos] [--best-effort|--strict]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: $0 [--profile personal|work] [--platform ubuntu|fedora|arch|macos] [--best-effort|--strict]"
      exit 1
      ;;
  esac
done

show_welcome_screen
resolve_chezmoi_dir
resolve_platform

if [ -z "$profile" ]; then
  choose_profile
fi

case "$profile" in
  personal|work)
    ;;
  *)
    echo "Invalid profile: $profile"
    echo "Use --profile personal or --profile work."
    exit 1
    ;;
esac

# chezmoi init persists this into its config so a later plain `chezmoi apply`
# uses the same profile the bootstrap ran with.
export DOTFILES_PROFILE="$profile"

case "$setup_mode" in
  best_effort|strict)
    ;;
  *)
    echo "Invalid setup mode: $setup_mode"
    echo "Use --best-effort, --strict, or DOTFILES_SETUP_MODE=best_effort|strict."
    exit 1
    ;;
esac

trap on_exit EXIT

ensure_linux_sudo_access

if [ "$OS" = "Linux" ]; then
  if is_ci; then
    echo "Skipping system package refresh in lightweight CI mode."
    record_outcome skipped "System package refresh" "Skipped in lightweight CI mode."
  else
    run_step "System package refresh" update_system
  fi
fi

run_step "Download tool (curl or wget)" ensure_download_tool
run_step "Git" ensure_git

if ! have chezmoi; then
  run_step --critical "Install chezmoi" install_chezmoi
  export PATH="$HOME/.local/bin:$PATH"
  hash -r
elif is_ci; then
  echo "Skipping chezmoi self-upgrade in lightweight CI mode."
  record_outcome skipped "Upgrade chezmoi" "Skipped in lightweight CI mode."
else
  run_step "Upgrade chezmoi" upgrade_chezmoi
fi

if using_checked_out_source; then
  run_step "Initialize chezmoi from the checked-out source" init_chezmoi_from_source
elif [ ! -d "$chezmoi_dir/.git" ]; then
  if [ -z "$repo" ]; then
    abort "DOTFILES_REPO is required when installing from a downloaded bootstrap script. Set it to your repository URL, for example: https://github.com/USER/dotfiles.git"
  fi
  run_step --critical "Clone the dotfiles repository with chezmoi init" init_chezmoi_from_repo
else
  run_step "Refresh the dotfiles repository" refresh_repo
fi

if ! have ansible-playbook; then
  run_step --critical "Install Ansible" install_ansible
fi
run_step "Refresh Ansible collections from Galaxy" refresh_ansible_collections
run_step --critical "Required Ansible collections" verify_ansible_collections

cd "$chezmoi_dir"
export DOTFILES_CHEZMOI_DIR="$chezmoi_dir"
ansible_playbook="ansible/playbooks/$platform.yml"
if [ ! -f "$ansible_playbook" ]; then
  abort "No Ansible playbook exists for platform: $platform"
fi

ansible_args=(-i "localhost," "$ansible_playbook")
if [ -n "$profile" ]; then
  ansible_args+=(-e "profile=$profile")
fi
ansible_args+=(-e "dotfiles_setup_mode=$setup_mode")

if [ "$OS" = "Linux" ] && [ -n "$become_password_file" ]; then
  export DOTFILES_SUDO_PASSWORD_FILE="$become_password_file"
  ansible_args=(--become-password-file "$become_password_file" "${ansible_args[@]}")
fi

write_bootstrap_outcomes_file
export DOTFILES_BOOTSTRAP_OUTCOMES_FILE="$bootstrap_outcomes_file"

# Ansible writes the report itself; the stamp tells the EXIT trap whether the
# report on disk is from this run or left over from an earlier one.
report_stamp_file="$(mktemp)"
ansible_log="$(mktemp)"
if [ -t 1 ]; then
  export ANSIBLE_FORCE_COLOR=1
fi

ansible_started=1
set +e
ANSIBLE_CONFIG="$chezmoi_dir/ansible.cfg" ansible-playbook "${ansible_args[@]}" 2>&1 | tee "$ansible_log"
ansible_exit_code="${PIPESTATUS[0]}"
set -e

if [ -f "$report_file" ] && [ "$report_file" -nt "$report_stamp_file" ]; then
  report_written_by_ansible=1
fi

exit "$ansible_exit_code"
