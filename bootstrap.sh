#!/usr/bin/env bash
set -euo pipefail

repo="https://github.com/Patruxs/dotfiles.git"
chezmoi_dir="$HOME/.local/share/chezmoi"

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

OS="$(uname -s)"
DISTRO=""
if [ "$OS" = "Linux" ] && [ -f /etc/os-release ]; then
  . /etc/os-release
  DISTRO="$ID"
fi

have() {
  command -v "$1" >/dev/null 2>&1
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
        sudo dnf install -y "$@"
        ;;
      debian|ubuntu)
        sudo apt-get update && sudo apt-get install -y "$@"
        ;;
      arch|manjaro)
        sudo pacman -Sy --noconfirm --needed "$@"
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

choose_profile() {
  local tty_device
  local choice

  if [ -n "${DOTFILES_PROFILE:-}" ]; then
    profile="${DOTFILES_PROFILE}"
    return
  fi

  if has_interactive_tty && [ -r /dev/tty ] && [ -w /dev/tty ]; then
    tty_device="/dev/tty"
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

# Ask for the administrator password upfront
sudo -v
# Keep-alive: update existing sudo time stamp until this script has finished
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

ensure_download_tool
ensure_git

if ! have chezmoi; then
  mkdir -p "$HOME/.local/bin"
  fetch_to_stdout "https://get.chezmoi.io/lb" | sh -s -- -b "$HOME/.local/bin"
  export PATH="$HOME/.local/bin:$PATH"
fi

if [ ! -d "$chezmoi_dir/.git" ]; then
  chezmoi init "$repo"
fi

if ! have ansible-playbook; then
  install_ansible
fi

profile=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --profile)
      profile="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

show_welcome_screen

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

extra_vars=""
if [ -n "$profile" ]; then
  extra_vars="-e profile=$profile"
fi

cd "$chezmoi_dir"
ANSIBLE_CONFIG="$chezmoi_dir/ansible.cfg" ansible-playbook -i "localhost," "ansible/playbooks/setup.yml" $extra_vars
