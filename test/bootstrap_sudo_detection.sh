#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP="$REPO_ROOT/bootstrap.sh"

extract_function() {
  local function_name="$1"

  awk -v fn="$function_name" '
    $0 ~ "^" fn "\\(\\) \\{" { printing = 1 }
    printing { print }
    printing && $0 == "}" { exit }
  ' "$BOOTSTRAP"
}

tmpdir="$(mktemp -d)"

cleanup() {
  rm -rf "$tmpdir"
  if [ -n "${become_password_file:-}" ] && [ -f "$become_password_file" ]; then
    rm -f "$become_password_file"
  fi
}

trap cleanup EXIT

cat >"$tmpdir/sudo" <<'EOF'
#!/usr/bin/env bash
if [ "$#" -eq 2 ] && [ "$1" = "-n" ] && [ "$2" = "true" ]; then
  exit 0
fi

if [ "$#" -eq 3 ] && [ "$1" = "-k" ] && [ "$2" = "-n" ] && [ "$3" = "true" ]; then
  exit 1
fi

if [ "$#" -eq 3 ] && [ "$1" = "-n" ] && [ "$2" = "-k" ] && [ "$3" = "true" ]; then
  exit 1
fi

exit 0
EOF
chmod +x "$tmpdir/sudo"

PATH="$tmpdir:$PATH"
OS="Linux"
sudo_password=""
become_password_file=""

is_ci() {
  return 1
}

prompt_sudo_password() {
  sudo_password="secret"
}

validate_sudo_password() {
  :
}

eval "$(extract_function have)"
eval "$(extract_function create_become_password_file)"
eval "$(extract_function have_passwordless_sudo)"
eval "$(extract_function ensure_linux_sudo_access)"

ensure_linux_sudo_access

if [ -z "$become_password_file" ]; then
  echo "expected bootstrap to create a become password file when only cached sudo is available"
  exit 1
fi

if [ "$(cat "$become_password_file")" != "secret" ]; then
  echo "expected bootstrap to persist the prompted sudo password"
  exit 1
fi

echo "bootstrap sudo detection passed"
