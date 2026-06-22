#!/usr/bin/env bash
set -euo pipefail

repo="https://github.com/Patruxs/dotfiles.git"
chezmoi_dir="$HOME/.local/share/chezmoi"

# Ask for the administrator password upfront
sudo -v
# Keep-alive: update existing sudo time stamp until this script has finished
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

OS="$(uname -s)"
DISTRO=""
if [ "$OS" = "Linux" ] && [ -f /etc/os-release ]; then
  . /etc/os-release
  DISTRO="$ID"
fi

have() {
  command -v "$1" >/dev/null 2>&1
}

if ! have chezmoi; then
  mkdir -p "$HOME/.local/bin"
  sh -c "$(curl -fsLS https://get.chezmoi.io/lb)" -- -b "$HOME/.local/bin"
  export PATH="$HOME/.local/bin:$PATH"
fi

if [ ! -d "$chezmoi_dir/.git" ]; then
  chezmoi init "$repo"
fi

install_ansible() {
  echo "Ansible not found. Installing..."
  if [ "$OS" = "Darwin" ]; then
    if ! have brew; then
      echo "Homebrew not found. Please install Homebrew first."
      exit 1
    fi
    brew install ansible
  elif [ "$OS" = "Linux" ]; then
    case "$DISTRO" in
      fedora)
        sudo dnf install -y ansible
        ;;
      debian|ubuntu)
        sudo apt-get update && sudo apt-get install -y ansible
        ;;
      arch|manjaro)
        sudo pacman -S --noconfirm ansible
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

extra_vars=""
if [ -n "$profile" ]; then
  extra_vars="-e profile=$profile"
fi

cd "$chezmoi_dir"
ANSIBLE_CONFIG="$chezmoi_dir/ansible.cfg" ansible-playbook "ansible/playbooks/setup.yml" $extra_vars
