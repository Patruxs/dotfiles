#!/usr/bin/env bash
# shellcheck disable=SC2034  # globals below are consumed by the bootstrap functions eval'd from bootstrap.sh
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
}

trap cleanup EXIT

fail() {
  echo "$1" >&2
  exit 1
}

OS="Linux"
setup_mode="best_effort"
profile="personal"
platform="ubuntu"
desktop="kde"
desktop_detail="XDG_CURRENT_DESKTOP=KDE"
report_file="$tmpdir/report.md"
bootstrap_outcome_status=()
bootstrap_outcome_name=()
bootstrap_outcome_detail=()
bootstrap_failure_count=0
bootstrap_abort_reason=""
bootstrap_outcomes_file=""
ansible_log=""
ansible_exit_code=""
ansible_started=0
progress_enabled=0
progress_total=0
progress_done=0
progress_label=""
progress_phase_index=""
progress_ansible_phases=(
  "profile_preflight : "
  "low_memory : "
  "chezmoi_setup_data : "
  "package_installer : "
  "features/"
  "chezmoi : "
  "services : "
  "setup_outcome : "
)

eval "$(extract_function progress_draw)"
eval "$(extract_function progress_set_label)"
eval "$(extract_function progress_advance)"
eval "$(extract_function progress_ansible_phase_index)"
eval "$(extract_function strip_ansi)"
eval "$(extract_function sanitize_captured_output)"
eval "$(extract_function json_escape)"
eval "$(extract_function abort)"
eval "$(extract_function record_outcome)"
eval "$(extract_function run_step)"
eval "$(extract_function write_bootstrap_outcomes_file)"
eval "$(extract_function write_fallback_report)"

for required in progress_draw progress_set_label progress_advance progress_ansible_phase_index strip_ansi sanitize_captured_output json_escape abort record_outcome run_step write_bootstrap_outcomes_file write_fallback_report; do
  if ! declare -F "$required" >/dev/null; then
    fail "expected bootstrap.sh to define $required"
  fi
done

run_step "Works" true >/dev/null
if [ "${bootstrap_outcome_status[0]}" != "ok" ] || [ "${bootstrap_outcome_name[0]}" != "Works" ]; then
  fail "expected a succeeding step to be recorded as ok"
fi

failing_step() {
  echo "Reading package lists..."
  echo "E: Unable to locate package example" >&2
  exit 3
}
run_step "Breaks" failing_step >/dev/null
if [ "$bootstrap_failure_count" -ne 1 ]; then
  fail "expected the failing step to be counted as a failure"
fi
if [ "${bootstrap_outcome_status[1]}" != "failed" ]; then
  fail "expected the failing step to be recorded as failed"
fi
case "${bootstrap_outcome_detail[1]}" in
  "Exit status 3: E: Unable to locate package example"*) ;;
  *) fail "expected the failure detail to lead with the exit status and the last error line, got: ${bootstrap_outcome_detail[1]}" ;;
esac
case "${bootstrap_outcome_detail[1]}" in
  *"Reading package lists..."*) ;;
  *) fail "expected the failure detail to keep the captured step output" ;;
esac

partial_step() {
  false
  echo "should not run"
}
run_step "Partial" partial_step >/dev/null
case "${bootstrap_outcome_detail[2]}" in
  *"should not run"*) fail "expected a failing command to stop the rest of its step" ;;
esac

if (setup_mode="strict"; run_step "Strict" false >/dev/null 2>&1); then
  fail "expected strict mode to exit on a failed step"
fi

if (run_step --critical "Critical" false >/dev/null 2>&1); then
  fail "expected a critical step failure to exit"
fi

progress_step() {
  printf 'Downloading  10%%\r  50%%\r 100%%\n'
  printf '%s[0;31mE: download failed%s[0m\n' "$(printf '\033')" "$(printf '\033')"
  exit 4
}
run_step "Progress" progress_step >/dev/null
case "${bootstrap_outcome_detail[3]}" in
  *"$(printf '\r')"*) fail "expected carriage returns to be stripped from captured step output" ;;
  *"$(printf '\033')"*) fail "expected ANSI escape sequences to be stripped from captured step output" ;;
  "Exit status 4: E: download failed"*) ;;
  *) fail "expected the progress step failure to lead with the real error line, got: ${bootstrap_outcome_detail[3]}" ;;
esac

record_outcome skipped "Optional" "Skipped in lightweight CI mode."

awkward_detail="$(printf 'line with "quotes" and back\\slash\n\tindented tab line')"
record_outcome failed "Awkward" "$awkward_detail"
record_outcome failed "Control" "$(printf 'before\rafter\033[0m\007')"
write_bootstrap_outcomes_file
if [ ! -s "$bootstrap_outcomes_file" ]; then
  fail "expected the bootstrap outcomes file to be written"
fi
if [ "$(wc -l <"$bootstrap_outcomes_file" | tr -d ' ')" -ne 7 ]; then
  fail "expected one JSON line per recorded outcome"
fi
if grep -q "$(printf '\r')" "$bootstrap_outcomes_file"; then
  fail "expected the outcomes file to contain no raw carriage returns"
fi
if command -v python3 >/dev/null 2>&1; then
  python3 - "$bootstrap_outcomes_file" "$awkward_detail" <<'PY' || fail "expected the outcomes file to parse as JSON lines and round-trip the detail text"
import json
import sys

path, expected = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8", newline="") as handle:
    entries = [json.loads(line) for line in handle.read().split("\n") if line.strip()]
assert entries[0] == {"status": "ok", "name": "Works", "detail": ""}, entries[0]
assert entries[1]["status"] == "failed" and entries[1]["name"] == "Breaks", entries[1]
assert entries[4] == {"status": "skipped", "name": "Optional", "detail": "Skipped in lightweight CI mode."}, entries[4]
assert entries[5]["detail"] == expected, entries[5]
assert entries[6]["detail"] == "beforeafter[0m", entries[6]
PY
else
  if ! grep -Fq '{"status":"ok","name":"Works","detail":""}' "$bootstrap_outcomes_file"; then
    fail "expected the outcomes file to contain JSON objects"
  fi
fi
rm -f "$bootstrap_outcomes_file"

ansible_started=1
ansible_exit_code=2
ansible_log="$tmpdir/ansible.log"
printf 'TASK [something]\n%s[0;31mfatal: [localhost]: FAILED! => {"msg": "boom"}%s[0m\n' "$(printf '\033')" "$(printf '\033')" >"$ansible_log"
write_fallback_report 2
if [ ! -s "$report_file" ]; then
  fail "expected the fallback report to be written"
fi
for needle in \
  '# Dotfiles setup report' \
  "- Desktop: \`kde\` (XDG_CURRENT_DESKTOP=KDE)" \
  '- Result: Aborted: the Ansible playbook exited with status 2' \
  '## Errors' \
  '### [bootstrap] Breaks' \
  'E: Unable to locate package example' \
  '### [ansible] ansible/playbooks/ubuntu.yml' \
  'fatal: [localhost]: FAILED! => {"msg": "boom"}' \
  '## Completed steps' \
  '- [bootstrap] Works' \
  '- [bootstrap] Optional: skipped - Skipped in lightweight CI mode.' \
  '## Next steps'; do
  if ! grep -Fq -- "$needle" "$report_file"; then
    fail "expected the fallback report to contain: $needle"
  fi
done
if grep -q "$(printf '\033')" "$report_file"; then
  fail "expected the fallback report to strip ANSI escape sequences"
fi

progress_ansible_phase_index "Gathering Facts"
if [ -n "$progress_phase_index" ]; then
  fail "expected a task outside the playbook phases to map to no phase"
fi
progress_ansible_phase_index "chezmoi_setup_data : Write setup data"
if [ "$progress_phase_index" != "3" ]; then
  fail "expected chezmoi_setup_data tasks to map to phase 3, got '$progress_phase_index'"
fi
progress_ansible_phase_index "chezmoi : Apply managed files"
if [ "$progress_phase_index" != "6" ]; then
  fail "expected chezmoi tasks to map to phase 6, got '$progress_phase_index'"
fi
progress_ansible_phase_index "features/flatpak_apps : Install Flatpak apps"
if [ "$progress_phase_index" != "5" ]; then
  fail "expected feature role tasks to map to phase 5, got '$progress_phase_index'"
fi

progress_total=2
progress_done=0
run_step "Counted" true >/dev/null
run_step "Counted failure" false >/dev/null
run_step "Past the end" true >/dev/null
if [ "$progress_done" -ne 2 ]; then
  fail "expected run_step to advance the progress bar to 2 of 2, got $progress_done"
fi

echo "bootstrap best-effort step handling passed"
