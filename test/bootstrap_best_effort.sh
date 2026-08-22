#!/usr/bin/env bash
# shellcheck disable=SC2034  # globals below are consumed by the bootstrap functions eval'd from bootstrap.sh
# Exercises the bootstrap.sh step runner and report writer in isolation:
# failed steps are recorded and skipped in best-effort mode, stop the run in
# strict mode or when critical, and always end up in a Markdown report.
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

# Globals the extracted functions read and write.
setup_mode="best_effort"
profile="personal"
platform="ubuntu"
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

eval "$(extract_function strip_ansi)"
eval "$(extract_function sanitize_captured_output)"
eval "$(extract_function json_escape)"
eval "$(extract_function abort)"
eval "$(extract_function record_outcome)"
eval "$(extract_function run_step)"
eval "$(extract_function write_bootstrap_outcomes_file)"
eval "$(extract_function write_fallback_report)"

for required in strip_ansi sanitize_captured_output json_escape abort record_outcome run_step write_bootstrap_outcomes_file write_fallback_report; do
  if ! declare -F "$required" >/dev/null; then
    fail "expected bootstrap.sh to define $required"
  fi
done

# 1. A succeeding step is recorded as ok.
run_step "Works" true >/dev/null
if [ "${bootstrap_outcome_status[0]}" != "ok" ] || [ "${bootstrap_outcome_name[0]}" != "Works" ]; then
  fail "expected a succeeding step to be recorded as ok"
fi

# 2. A failing step is recorded, skipped, and does not stop the run.
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

# 3. A multi-command step stops at its first failing command.
partial_step() {
  false
  echo "should not run"
}
run_step "Partial" partial_step >/dev/null
case "${bootstrap_outcome_detail[2]}" in
  *"should not run"*) fail "expected a failing command to stop the rest of its step" ;;
esac

# 4. Strict mode stops at the first failure.
if (setup_mode="strict"; run_step "Strict" false >/dev/null 2>&1); then
  fail "expected strict mode to exit on a failed step"
fi

# 5. Critical steps stop the run even in best-effort mode.
if (run_step --critical "Critical" false >/dev/null 2>&1); then
  fail "expected a critical step failure to exit"
fi

# 6. Carriage-return progress output and colour codes never reach the record.
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

# 7. Skipped steps are recorded with their reason.
record_outcome skipped "Optional" "Skipped in lightweight CI mode."

# 8. The Ansible handoff file is valid JSON lines that round-trip awkward text,
#    and a stray control character recorded directly still cannot break it.
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

# 9. The fallback report is Markdown, names the abort, quotes failures, strips
#    ANSI colour from the captured Ansible log, and lists completed steps.
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

echo "bootstrap best-effort step handling passed"
