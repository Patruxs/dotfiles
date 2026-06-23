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

run_sudo() {
  printf '%s\n' "$sudo_password" | sudo -S -p '' "$@"
}

create_become_password_file() {
  become_password_file="$(mktemp)"
  chmod 700 "$become_password_file"
  cat >"$become_password_file" <<EOF
#!/usr/bin/env bash
printf '%s\n' "$(printf '%s' "$sudo_password" | sed "s/'/'\\\\''/g")"
EOF
}

refresh_repo() {
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
        run_sudo dnf install -y "$@"
        ;;
      debian|ubuntu)
        run_sudo apt-get install -y "$@"
        ;;
      arch|manjaro)
        run_sudo pacman -S --noconfirm --needed "$@"
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

  echo "Updating system packages before setup..."
  case "$DISTRO" in
    fedora)
      run_sudo dnf upgrade --refresh -y
      ;;
    debian|ubuntu)
      run_sudo apt-get update
      run_sudo apt-get upgrade -y
      ;;
    arch|manjaro)
      run_sudo pacman -Syu --noconfirm
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

trap cleanup_sensitive_state EXIT

prompt_sudo_password
validate_sudo_password
create_become_password_file

update_system

ensure_download_tool
ensure_git

if ! have chezmoi; then
  mkdir -p "$HOME/.local/bin"
  fetch_to_stdout "https://get.chezmoi.io/lb" | sh -s -- -b "$HOME/.local/bin"
  export PATH="$HOME/.local/bin:$PATH"
fi

if [ ! -d "$chezmoi_dir/.git" ]; then
  chezmoi init "$repo"
else
  refresh_repo
fi

if ! have ansible-playbook; then
  install_ansible
fi

cd "$chezmoi_dir"
ansible_args=(-i "localhost," "ansible/playbooks/setup.yml")
if [ -n "$profile" ]; then
  ansible_args+=(-e "profile=$profile")
fi

if [ "$OS" = "Linux" ]; then
  ansible_args=(--become-password-file "$become_password_file" "${ansible_args[@]}")
fi

ANSIBLE_CONFIG="$chezmoi_dir/ansible.cfg" ansible-playbook "${ansible_args[@]}"
