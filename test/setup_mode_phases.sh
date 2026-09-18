#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo "ansible-playbook not found, skipping setup mode phase checks."
  exit 0
fi

failures=0
fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/roles/works/tasks" "$work/roles/breaks/tasks" "$work/bin"
cat >"$work/roles/works/tasks/main.yml" <<'YAML'
---
- name: Succeed
  ansible.builtin.command: "true"
  changed_when: false
YAML
cat >"$work/roles/breaks/tasks/main.yml" <<'YAML'
---
- name: Break loudly
  ansible.builtin.shell: echo phase-boom >&2; exit 3
  changed_when: false
YAML

cat >"$work/bin/fakepkg" <<'SH'
#!/usr/bin/env bash
shift
printf '%s\n' "$*" >>"$(dirname "$0")/fakepkg.log"
status=0
for package in "$@"; do
  case "$package" in
    present) ;;
    broken)
      echo "no such package: broken" >&2
      status=1
      ;;
    *) echo "installed $package" ;;
  esac
done
if [ "$status" -eq 0 ] && [ "$*" = "present" ]; then
  echo "NOTHING-TO-DO"
fi
exit "$status"
SH
chmod +x "$work/bin/fakepkg"

cat >"$work/bin/fakeindex" <<'SH'
#!/usr/bin/env bash
touch "$(dirname "$0")/index-refreshed"
if [ "${1:-}" = fail ]; then
  echo "index-boom" >&2
  exit 100
fi
echo "index refreshed"
SH
chmod +x "$work/bin/fakeindex"

cat >"$work/phases.yml" <<YAML
---
- name: Exercise the shared phase wrapper
  hosts: localhost
  connection: local
  gather_facts: false
  vars:
    dotfiles_setup_failures: []
    dotfiles_setup_configured: []
    dotfiles_setup_aborted: false
  tasks:
    - name: Run phases
      block:
        - name: Run one phase
          ansible.builtin.include_tasks: "$repo_root/ansible/playbooks/run_phase.yml"
          vars:
            phase:
              role: "{{ phase_role }}"
              key: feature
              name: "{{ phase_role }}"
              detail: "finished {{ phase_role }}"
          loop: [works, breaks, works]
          loop_control:
            loop_var: phase_role
      always:
        - name: Write the result
          ansible.builtin.copy:
            content: "{{ {'failures': dotfiles_setup_failures, 'configured': dotfiles_setup_configured, 'aborted': dotfiles_setup_aborted} | to_json }}"
            dest: "{{ result_file }}"
            mode: "0600"
YAML

cat >"$work/packages.yml" <<YAML
---
- name: Exercise the Linux package installer
  hosts: localhost
  connection: local
  gather_facts: false
  vars:
    ansible_become: false
    dotfiles_setup_failures: []
    dotfiles_setup_aborted: false
    system_packages: [good, broken, present, later]
    dotfiles_platform:
      package_family: fake
      package_index_refresh_command: "{{ index_refresh_command | default([]) }}"
      package_install_command: ["$work/bin/fakepkg", install]
      package_install_serial_command: ["$work/bin/fakepkg", install]
      package_install_noop_marker: NOTHING-TO-DO
  tasks:
    - name: Install packages
      block:
        - name: Run the Linux package tasks
          ansible.builtin.include_tasks: "$repo_root/ansible/roles/package_installer/tasks/linux.yml"
      always:
        - name: Write the result
          ansible.builtin.copy:
            content: "{{ {'failures': dotfiles_setup_failures, 'aborted': dotfiles_setup_aborted, 'attempted': (dotfiles_system_package_installs.results | default([]) | rejectattr('skipped', 'defined') | map(attribute='item') | list)} | to_json }}"
            dest: "{{ result_file }}"
            mode: "0600"
YAML

run_playbook() {
  local playbook="$1" result="$2"
  shift 2
  ANSIBLE_ROLES_PATH="$work/roles:$repo_root/ansible/roles" ANSIBLE_LOCALHOST_WARNING=False ANSIBLE_INVENTORY_UNPARSED_WARNING=False \
    ansible-playbook -i localhost, "$playbook" -e "result_file=$result" "$@" >"$result.log" 2>&1
}

query() {
  python3 -c 'import json,sys; data=json.load(open(sys.argv[1])); print(eval(sys.argv[2], {"d": data}))' "$1" "$2"
}

expect() {
  local result="$1" expression="$2" expected="$3" label="$4" actual
  actual="$(query "$result" "$expression")"
  if [ "$actual" = "$expected" ]; then
    echo "ok: $label"
  else
    fail "$label: expected $expected, got $actual"
    cat "$result.log" >&2
  fi
}

result="$work/phases-best-effort.json"
if run_playbook "$work/phases.yml" "$result" -e dotfiles_setup_mode=best_effort; then
  echo "ok: best_effort keeps the play successful after a failing phase"
else
  fail "best_effort play failed"
  cat "$result.log" >&2
fi
expect "$result" "[c['name'] for c in d['configured']]" "['works', 'works']" "best_effort runs the phases after a failing one"
expect "$result" "[(f['phase'], f['name'], f['task'], f['error']) for f in d['failures']]" "[('feature', 'breaks', 'Break loudly', 'phase-boom')]" "best_effort records the failing phase, task and stderr"
expect "$result" "d['aborted']" "False" "best_effort does not mark the run aborted"

result="$work/phases-strict.json"
if run_playbook "$work/phases.yml" "$result" -e dotfiles_setup_mode=strict; then
  fail "strict play succeeded despite a failing phase"
else
  echo "ok: strict fails the play at the failing phase"
fi
expect "$result" "[c['name'] for c in d['configured']]" "['works']" "strict stops before later phases"
expect "$result" "[(f['phase'], f['name'], f['error']) for f in d['failures']]" "[('feature', 'breaks', 'phase-boom')]" "strict records the failure exactly once"
expect "$result" "d['aborted']" "True" "strict marks the run aborted"

result="$work/packages-best-effort.json"
if run_playbook "$work/packages.yml" "$result" -e dotfiles_setup_mode=best_effort; then
  echo "ok: best_effort package installs keep the play successful"
else
  fail "best_effort package play failed"
  cat "$result.log" >&2
fi
expect "$result" "d['attempted']" "['good', 'broken', 'present', 'later']" "best_effort attempts every package one at a time"
expect "$result" "[(f['phase'], f['name'], f['error']) for f in d['failures']]" "[('fake_package', 'broken', 'no such package: broken')]" "best_effort records the failed package"
if grep -Eq 'changed=2 ' "$result.log"; then
  echo "ok: only packages the installer acted on are reported as changed"
else
  fail "expected exactly the two installed packages to report changed"
  cat "$result.log" >&2
fi

result="$work/packages-strict.json"
if run_playbook "$work/packages.yml" "$result" -e dotfiles_setup_mode=strict; then
  fail "strict package play succeeded despite a broken package"
else
  echo "ok: strict package installs fail the play"
fi
expect "$result" "d['attempted']" "[]" "strict installs all packages in one transaction"

result="$work/packages-strict-low-memory.json"
if run_playbook "$work/packages.yml" "$result" -e dotfiles_setup_mode=strict -e dotfiles_low_memory_setup=true; then
  fail "strict low-memory package play succeeded despite a broken package"
else
  echo "ok: strict low-memory package installs fail the play"
fi
expect "$result" "'good' in d['attempted'] and 'broken' in d['attempted']" "True" "strict low-memory installs one package at a time"

result="$work/packages-index-best-effort.json"
rm -f "$work/bin/index-refreshed"
if run_playbook "$work/packages.yml" "$result" -e dotfiles_setup_mode=best_effort -e "{\"index_refresh_command\": [\"$work/bin/fakeindex\", \"fail\"]}"; then
  echo "ok: best_effort survives a failed package index refresh"
else
  fail "best_effort package play failed after a failed package index refresh"
  cat "$result.log" >&2
fi
[ -e "$work/bin/index-refreshed" ] || fail "expected the package index refresh command to run"
expect "$result" "[(f['phase'], f['name'], f['error']) for f in d['failures']][0]" "('fake_package', 'package index refresh', 'index-boom')" "best_effort records the failed package index refresh"
expect "$result" "d['attempted']" "['good', 'broken', 'present', 'later']" "best_effort still installs packages from the existing index"

result="$work/packages-index-strict.json"
rm -f "$work/bin/fakepkg.log"
if run_playbook "$work/packages.yml" "$result" -e dotfiles_setup_mode=strict -e "{\"index_refresh_command\": [\"$work/bin/fakeindex\", \"fail\"]}"; then
  fail "strict package play succeeded despite a failed package index refresh"
else
  echo "ok: strict stops at a failed package index refresh"
fi
expect "$result" "[(f['phase'], f['name'], f['error']) for f in d['failures']]" "[('fake_package', 'package index refresh', 'index-boom')]" "strict records the failed package index refresh once"
if [ -e "$work/bin/fakepkg.log" ]; then
  fail "expected strict mode to stop before installing packages, but the installer ran: $(cat "$work/bin/fakepkg.log")"
else
  echo "ok: strict installs nothing after a failed package index refresh"
fi

result="$work/packages-index-ok.json"
if run_playbook "$work/packages.yml" "$result" -e dotfiles_setup_mode=best_effort -e "{\"index_refresh_command\": [\"$work/bin/fakeindex\"]}"; then
  echo "ok: a successful package index refresh keeps the play successful"
else
  fail "best_effort package play failed with a working package index refresh"
  cat "$result.log" >&2
fi
expect "$result" "[f['name'] for f in d['failures']]" "['broken']" "a successful package index refresh records no failure"
if grep -Eq 'changed=2 ' "$result.log"; then
  echo "ok: the package index refresh is not reported as a change"
else
  fail "expected the package index refresh to leave the changed count at the two installed packages"
  cat "$result.log" >&2
fi

if [ "$failures" -gt 0 ]; then
  echo "setup mode phase checks failed: $failures" >&2
  exit 1
fi
echo "setup mode phase checks passed"
