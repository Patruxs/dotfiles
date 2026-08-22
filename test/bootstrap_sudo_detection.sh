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
# shellcheck disable=SC2034  # consumed by the bootstrap functions eval'd below
OS="Linux"
# shellcheck disable=SC2034  # consumed by the bootstrap functions eval'd below
sudo_password=""
become_password_file=""

is_ci() {
  return 1
}

# shellcheck disable=SC2329  # invoked by the bootstrap functions eval'd below
prompt_sudo_password() {
  # shellcheck disable=SC2034  # consumed by the bootstrap functions eval'd below
  sudo_password="secret"
}

validate_sudo_password() {
  :
}

# macOS-only gates: the test host is Linux, so stand in for an admin account
# with a terminal; the sudo detection under test is the same on both.
# shellcheck disable=SC2329  # invoked by the bootstrap functions eval'd below
is_macos_admin() {
  return 0
}

# shellcheck disable=SC2329  # invoked by the bootstrap functions eval'd below
have_tty_device() {
  return 0
}

# shellcheck disable=SC2329  # invoked by the bootstrap functions eval'd below
skip_macos_sudo() {
  echo "unexpected macOS sudo skip: $1"
  exit 1
}

eval "$(extract_function have)"
eval "$(extract_function create_become_password_file)"
eval "$(extract_function have_passwordless_sudo)"
eval "$(extract_function ensure_sudo_access)"

for os in Linux Darwin; do
  # shellcheck disable=SC2034  # consumed by the bootstrap functions eval'd below
  OS="$os"
  sudo_password=""
  become_password_file=""
  ensure_sudo_access

  if [ -z "$become_password_file" ]; then
    echo "expected bootstrap to create a become password file on $os when only cached sudo is available"
    exit 1
  fi

  if [ "$(cat "$become_password_file")" != "secret" ]; then
    echo "expected bootstrap to persist the prompted sudo password on $os"
    exit 1
  fi
  rm -f "$become_password_file"
done

# A non-admin macOS account must degrade with a warning, never abort.
# shellcheck disable=SC2329  # invoked by the bootstrap functions eval'd above
is_macos_admin() {
  return 1
}
# shellcheck disable=SC2329  # invoked by the bootstrap functions eval'd above
skip_macos_sudo() {
  :
}
# shellcheck disable=SC2034  # consumed by the bootstrap functions eval'd above
OS="Darwin"
# shellcheck disable=SC2034  # consumed by the bootstrap functions eval'd above
sudo_password=""
become_password_file=""
# shellcheck disable=SC2329  # invoked by the bootstrap functions eval'd above
prompt_sudo_password() {
  echo "expected bootstrap not to prompt a non-admin macOS account for a sudo password"
  exit 1
}
ensure_sudo_access
if [ -n "$become_password_file" ]; then
  echo "expected no become password file for a non-admin macOS account"
  exit 1
fi

if false; then
  echo "unreachable"
  exit 1
fi

echo "bootstrap sudo detection passed"
