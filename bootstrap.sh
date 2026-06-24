#!/usr/bin/env bash
set -euo pipefail

repo="https://github.com/Patruxs/dotfiles.git"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
chezmoi_dir="$HOME/.local/share/chezmoi"
OS="$(uname -s)"
DISTRO=""
platform=""

if [ "$OS" = "Linux" ] && [ -f /etc/os-release ]; then
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

is_automation() {
  case "${GITHUB_ACTIONS:-${CI:-${DOTFILES_CI:-}}}" in
    1|true|TRUE|yes|YES)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

using_checked_out_source() {
  is_automation &&
    [ -d "$script_dir/.git" ] &&
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
    echo "A sudo password is required for setup."
    exit 1
  fi
}

validate_sudo_password() {
  if ! printf '%s\n' "$sudo_password" | sudo -S -k -p '' -v >/dev/null 2>&1; then
    echo "The provided sudo password was not accepted."
    exit 1
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
    echo "sudo is required for Linux setup."
    exit 1
  fi

  if have_passwordless_sudo; then
    return
  fi

  if is_ci; then
    echo "CI Linux setup requires passwordless sudo."
    exit 1
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
        run_privileged apt-get install -y "$@"
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

update_system() {
  if [ "$OS" != "Linux" ]; then
    return
  fi

  if is_ci; then
    echo "Skipping system package refresh in lightweight CI mode."
    return
  fi

  echo "Updating system packages before setup..."
  case "$DISTRO" in
    fedora)
      run_privileged dnf upgrade --refresh -y
      ;;
    debian|ubuntu)
      run_privileged apt-get update
      run_privileged apt-get upgrade -y
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

fetch_to_stdout() {
  if have curl; then
    curl -fsSL "$1"
  elif have wget; then
    wget -qO- "$1"
  else
    echo "Neither curl nor wget is available."
    exit 1
  fi
}

ensure_download_tool() {
  if have curl || have wget; then
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

ensure_ansible_collections() {
  local requirements_file

  requirements_file="$chezmoi_dir/ansible/collections/requirements.yml"

  if [ ! -f "$requirements_file" ] || ! have ansible-galaxy; then
    return
  fi

  echo "Installing or updating required Ansible collections..."
  ansible-galaxy collection install --upgrade -r "$requirements_file"
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
    --help|-h)
      echo "Usage: $0 [--profile personal|work] [--platform ubuntu|fedora|arch|macos]"
      exit 0
      ;;
    *)
      shift
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

trap cleanup_sensitive_state EXIT

ensure_linux_sudo_access

update_system

ensure_download_tool
ensure_git

if ! have chezmoi; then
  mkdir -p "$HOME/.local/bin"
  fetch_to_stdout "https://get.chezmoi.io/lb" | sh -s -- -b "$HOME/.local/bin"
  export PATH="$HOME/.local/bin:$PATH"
elif is_ci; then
  echo "Skipping chezmoi self-upgrade in lightweight CI mode."
else
  chezmoi upgrade || echo "Warning: could not self-upgrade chezmoi. Continuing with the current version."
fi

if [ ! -d "$chezmoi_dir/.git" ]; then
  chezmoi init "$repo"
else
  refresh_repo
fi

if ! have ansible-playbook; then
  install_ansible
fi
ensure_ansible_collections

cd "$chezmoi_dir"
export DOTFILES_CHEZMOI_DIR="$chezmoi_dir"
ansible_playbook="ansible/playbooks/$platform.yml"
if [ ! -f "$ansible_playbook" ]; then
  echo "No Ansible playbook exists for platform: $platform"
  exit 1
fi

ansible_args=(-i "localhost," "$ansible_playbook")
if [ -n "$profile" ]; then
  ansible_args+=(-e "profile=$profile")
fi

if [ "$OS" = "Linux" ] && [ -n "$become_password_file" ]; then
  export DOTFILES_SUDO_PASSWORD_FILE="$become_password_file"
  ansible_args=(--become-password-file "$become_password_file" "${ansible_args[@]}")
fi

ANSIBLE_CONFIG="$chezmoi_dir/ansible.cfg" ansible-playbook "${ansible_args[@]}"
