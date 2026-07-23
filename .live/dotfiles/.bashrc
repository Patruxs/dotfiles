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

if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init bash)"
fi

if command -v fzf >/dev/null 2>&1; then
  eval "$(fzf --bash)"
fi


# pnpm
export PNPM_HOME="/home/pat/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME/bin:"*) ;;
  *) export PATH="$PNPM_HOME/bin:$PATH" ;;
esac
# pnpm end


# >>> grok installer >>>
export PATH="$HOME/.grok/bin:$PATH"
[[ -r "$HOME/.grok/completions/bash/grok.bash" ]] && source "$HOME/.grok/completions/bash/grok.bash"
# <<< grok installer <<<

# >>> mamba initialize >>>
# !! Contents within this block are managed by 'micromamba shell init' !!
export MAMBA_EXE='/tmp/bin/micromamba';
export MAMBA_ROOT_PREFIX='/home/pat/.local/opt/micromamba';
__mamba_setup="$("$MAMBA_EXE" shell hook --shell bash --root-prefix "$MAMBA_ROOT_PREFIX" 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__mamba_setup"
else
    alias micromamba="$MAMBA_EXE"  # Fallback on help from micromamba activate
fi
unset __mamba_setup
# <<< mamba initialize <<<

eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)"
