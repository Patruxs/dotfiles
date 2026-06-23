# ~/.zshrc
HISTFILE="$HOME/.zsh_history"
HISTSIZE=10000
SAVEHIST=10000
setopt append_history
setopt share_history
setopt hist_ignore_dups
setopt hist_ignore_space
setopt hist_reduce_blanks
setopt auto_cd
setopt auto_menu
setopt complete_in_word
setopt always_to_end

autoload -Uz compinit
compinit
zmodload zsh/complist

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' group-name ''

bindkey -e
bindkey '^[[A' history-beginning-search-backward
bindkey '^[[B' history-beginning-search-forward
bindkey '^I' menu-select

find_sourceable_file() {
  local candidate

  for candidate in "$@"; do
    if [ -f "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

homebrew_prefix="${HOMEBREW_PREFIX:-}"
if [ -z "$homebrew_prefix" ] && command -v brew >/dev/null 2>&1; then
  homebrew_prefix="$(brew --prefix 2>/dev/null)"
fi

if command -v fzf >/dev/null 2>&1 && fzf --zsh >/dev/null 2>&1; then
  source <(fzf --zsh)
else
  fzf_key_bindings="$(find_sourceable_file \
    "${FZF_BASE:-}/shell/key-bindings.zsh" \
    "${homebrew_prefix:-}/opt/fzf/shell/key-bindings.zsh" \
    "${homebrew_prefix:-}/share/fzf/key-bindings.zsh" \
    /opt/homebrew/opt/fzf/shell/key-bindings.zsh \
    /usr/local/opt/fzf/shell/key-bindings.zsh \
    /home/linuxbrew/.linuxbrew/opt/fzf/shell/key-bindings.zsh \
    /usr/share/fzf/shell/key-bindings.zsh \
    /usr/local/share/fzf/key-bindings.zsh \
  )"
  [ -n "$fzf_key_bindings" ] && source "$fzf_key_bindings"
fi

zsh_autosuggestions="$(find_sourceable_file \
  "${homebrew_prefix:-}/share/zsh-autosuggestions/zsh-autosuggestions.zsh" \
  /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
  /usr/local/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
  /home/linuxbrew/.linuxbrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
  /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
)"
if [ -n "$zsh_autosuggestions" ]; then
  source "$zsh_autosuggestions"
  ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'
  bindkey '^F' autosuggest-accept
fi

zsh_syntax_highlighting="$(find_sourceable_file \
  "${homebrew_prefix:-}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" \
  /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
  /usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
  /home/linuxbrew/.linuxbrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
  /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
)"
if [ -n "$zsh_syntax_highlighting" ]; then
  source "$zsh_syntax_highlighting"
fi

unset fzf_key_bindings homebrew_prefix zsh_autosuggestions zsh_syntax_highlighting
unfunction find_sourceable_file

if command -v mise >/dev/null 2>&1; then
  eval "$(mise activate zsh)"
fi
