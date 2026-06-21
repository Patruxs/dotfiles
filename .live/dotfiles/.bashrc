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
