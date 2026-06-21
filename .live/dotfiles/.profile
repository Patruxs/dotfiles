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

export GOPATH="${GOPATH:-$HOME/go}"
path_prepend "$HOME/.local/go/bin"
path_prepend "$GOPATH/bin"

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
