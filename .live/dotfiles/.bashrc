# ~/.bashrc
if [ -f /etc/bashrc ]; then
  . /etc/bashrc
fi

if [ -f "$HOME/.profile" ]; then
  . "$HOME/.profile"
fi

if [ -d "$HOME/.bashrc.d" ]; then
  for rc in "$HOME"/.bashrc.d/*; do
    [ -f "$rc" ] && . "$rc"
  done
  unset rc
fi

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"

if command -v mise >/dev/null 2>&1; then
  eval "$(mise activate bash)"
fi

# Override flatpak to automatically generate wrappers in ~/.local/bin
flatpak() {
  command flatpak "$@"
  local ret=$?
  for arg in "$@"; do
    if [[ "$arg" == "install" || "$arg" == "update" || "$arg" == "remove" || "$arg" == "uninstall" ]]; then
      if command -v update-flatpak-wrappers >/dev/null 2>&1; then
        update-flatpak-wrappers
      fi
      break
    fi
  done
  return $ret
}
