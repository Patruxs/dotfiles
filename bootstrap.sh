#!/usr/bin/env bash
set -euo pipefail

repo="https://github.com/Patruxs/dotfiles.git"

have() {
  command -v "$1" >/dev/null 2>&1
}

confirm() {
  if [ "${DOTFILES_AUTO_INSTALL:-0}" = "1" ]; then
    return 0
  fi
  printf '%s [y/N] ' "$1" >&2
  read -r reply || true
  case "${reply:-}" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

if ! have chezmoi; then
  mkdir -p "$HOME/.local/bin"
  sh -c "$(curl -fsLS https://get.chezmoi.io/lb)" -- -b "$HOME/.local/bin"
  export PATH="$HOME/.local/bin:$PATH"
fi

chezmoi init "$repo"
chezmoi diff

if confirm "Apply dotfiles from $repo?"; then
  chezmoi apply -v
else
  exit 0
fi

if confirm "Switch chezmoi source remote to SSH?"; then
  git -C "$HOME/.local/share/chezmoi" remote set-url origin git@github.com:Patruxs/dotfiles.git
fi
