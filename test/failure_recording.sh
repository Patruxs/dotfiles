#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo "ansible-playbook not found, skipping failure recording checks."
  exit 0
fi

failures=0
fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/home"

cat >"$work/bin/mise" <<'SH'
#!/usr/bin/env bash
case "$*" in
  "ls --missing --json") echo '{"node": []}' ;;
  "outdated --json") echo '{}' ;;
  install)
    echo "mise-install-boom" >&2
    exit 1
    ;;
  upgrade)
    echo "mise-upgrade-stdout"
    exit 1
    ;;
  *) exit 2 ;;
esac
SH

cat >"$work/bin/chezmoi" <<'SH'
#!/usr/bin/env bash
while [ "$#" -gt 0 ]; do
  case "$1" in
    --source|--override-data) shift 2 ;;
    *) break ;;
  esac
done
case "$1" in
  managed) echo "/src/.chezmoiscripts/run_after_hello.sh" ;;
  target-path) echo "$HOME/hello.sh" ;;
  apply)
    if [[ " $* " == *" --exclude=scripts "* ]]; then
      echo "files-boom" >&2
    else
      echo "script-boom" >&2
    fi
    exit 1
    ;;
  *) exit 2 ;;
esac
SH
chmod +x "$work/bin/mise" "$work/bin/chezmoi"

cat >"$work/recorders.yml" <<YAML
---
- name: Exercise the best-effort failure recorders
  hosts: localhost
  connection: local
  gather_facts: false
  vars:
    dotfiles_setup_mode: best_effort
    dotfiles_setup_failures: []
    dotfiles_setup_aborted: false
    chezmoi_dir: "$work/source"
    profile: personal
    homebrew_brews: [fake-formula]
    homebrew_casks: [fake-cask]
  tasks:
    - name: Run the recorders
      block:
        - name: Run the mise tool lists
          ansible.builtin.include_role:
            name: mise_tools

        - name: Apply chezmoi
          ansible.builtin.include_role:
            name: chezmoi

        - name: Install Homebrew packages
          ansible.builtin.include_tasks: "$repo_root/ansible/roles/package_installer/tasks/macos.yml"
      always:
        - name: Write the result
          ansible.builtin.copy:
            content: "{{ {'failures': dotfiles_setup_failures, 'aborted': dotfiles_setup_aborted} | to_json }}"
            dest: "$work/result.json"
            mode: "0600"
YAML

if env HOME="$work/home" PATH="$work/bin:$PATH" \
  ANSIBLE_COLLECTIONS_PATH="$HOME/.ansible/collections:/usr/share/ansible/collections" \
  ANSIBLE_ROLES_PATH="$repo_root/ansible/roles" ANSIBLE_LOCALHOST_WARNING=False ANSIBLE_INVENTORY_UNPARSED_WARNING=False \
  ansible-playbook -i localhost, "$work/recorders.yml" >"$work/result.log" 2>&1; then
  echo "ok: best-effort recorders keep the play successful"
else
  fail "the best-effort recorder play failed"
  cat "$work/result.log" >&2
fi

query() {
  python3 -c 'import json,sys; data=json.load(open(sys.argv[1])); print(eval(sys.argv[2], {"d": data}))' "$work/result.json" "$1"
}

expect() {
  local expression="$1" expected="$2" label="$3" actual
  actual="$(query "$expression")"
  if [ "$actual" = "$expected" ]; then
    echo "ok: $label"
  else
    fail "$label: expected $expected, got $actual"
    cat "$work/result.log" >&2
  fi
}

expect "[(f['phase'], f['name'], f['task'], f['error']) for f in d['failures'] if f['phase'] == 'mise']" \
  "[('mise', 'mise install', 'Install missing mise tools (best effort)', 'mise-install-boom'), ('mise', 'mise upgrade', 'Upgrade mise tools (best effort)', 'mise-upgrade-stdout'), ('mise', 'node', 'Install missing mise tools (best effort)', 'mise still lists node as missing after \`mise install\`; run \`mise install node\` to see why it failed.')]" \
  "mise records install, upgrade and still-missing tools, falling back to stdout when stderr is empty"
expect "[(f['phase'], f['name'], f['error']) for f in d['failures'] if f['phase'].startswith('chezmoi')]" \
  "[('chezmoi', 'managed dotfiles', 'files-boom'), ('chezmoi_script', 'hello.sh', 'script-boom')]" \
  "chezmoi records the failed file apply and the failed script"
expect "[(f['phase'], f['name'], f['error'] != '') for f in d['failures'] if f['phase'].endswith('_package')]" \
  "[('brew_package', 'fake-formula', True), ('cask_package', 'fake-cask', True)]" \
  "Homebrew records each failed formula and cask with its error"
expect "d['aborted']" "False" "best-effort recorders do not mark the run aborted"

if [ "$failures" -gt 0 ]; then
  echo "failure recording checks failed: $failures" >&2
  exit 1
fi
echo "failure recording checks passed"
