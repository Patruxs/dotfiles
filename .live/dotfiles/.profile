# ~/.profile
path_prepend() {
  [ $# -eq 1 ] || return 0
  [ -n "$1" ] || return 0
  case ":$PATH:" in
    *":$1:"*) ;;
    *) PATH="$1${PATH:+:$PATH}" ;;
  esac
}

path_prepend "$HOME/bin"
path_prepend "$HOME/.local/bin"

case "$(uname -s)" in
  Darwin)
    if [ -d /opt/homebrew/bin ]; then
      path_prepend /opt/homebrew/bin
    elif [ -d /usr/local/bin ]; then
      path_prepend /usr/local/bin
    fi
    ;;
  MINGW*|MSYS*|CYGWIN*)
    path_prepend "$HOME/AppData/Local/Microsoft/WinGet/Links"
    ;;
esac

export GOPATH="${GOPATH:-$HOME/go}"
path_prepend "$HOME/.local/go/bin"
path_prepend "$GOPATH/bin"

export THESIS_DIR="/mnt/Working/Working/School/Y4_2/Thesis"
export PERSONAL_DIR="/mnt/Personal"

alias thesis='cd "$THESIS_DIR"'
alias personal='cd "$PERSONAL_DIR"'
alias cdt='cd "$THESIS_DIR"'
alias cdp='cd "$PERSONAL_DIR"'

if [ -d "$HOME/.local/share/JetBrains/Toolbox/scripts" ]; then
  path_prepend "$HOME/.local/share/JetBrains/Toolbox/scripts"
fi

if [ -d "$HOME/.opencode/bin" ]; then
  path_prepend "$HOME/.opencode/bin"
fi

if command -v pnpm >/dev/null 2>&1; then
  export PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}"
  mkdir -p "$PNPM_HOME"
  path_prepend "$PNPM_HOME"
fi

export PATH
