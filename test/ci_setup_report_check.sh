#!/usr/bin/env bash
set -euo pipefail

report_file="${1:-$HOME/.dotfiles_setup_report.md}"

if [ ! -f "$report_file" ]; then
  echo "Setup report not found at $report_file"
  exit 1
fi

if ! grep -Fxq -- '- Result: Completed successfully.' "$report_file"; then
  echo "Setup report does not say the run completed successfully:"
  cat "$report_file"
  exit 1
fi

echo "Setup report confirms a successful run."
