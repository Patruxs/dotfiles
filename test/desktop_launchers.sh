#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v chezmoi >/dev/null 2>&1; then
  echo "chezmoi is required for the desktop launcher checks." >&2
  exit 1
fi

failures=0
fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

ignored_launchers() {
  chezmoi execute-template --source "$repo_root" \
    --override-data "{\"dotfiles_desktop\":\"$1\",\"dotfiles_features\":$2}" <"$repo_root/home/.chezmoiignore" |
    grep -E '^\.local/share/applications/omarchy-[a-z-]+\.desktop$' || true
}

work_features='["mise","core_cli","desktop_base","ai_clis","ghostty_terminal"]'
personal_features='["mise","core_cli","desktop_base","desktop_apps","ai_clis","ghostty_terminal"]'

ignored="$(ignored_launchers kde "$work_features")"
for launcher in browser messenger music; do
  if grep -Fxq ".local/share/applications/omarchy-$launcher.desktop" <<<"$ignored"; then
    echo "ok: KDE without desktop_apps does not get the $launcher launcher"
  else
    fail "KDE without desktop_apps still gets omarchy-$launcher.desktop, whose app no feature installed"
  fi
done
if grep -Fxq ".local/share/applications/omarchy-ai-agent.desktop" <<<"$ignored"; then
  fail "the AI agent launcher is ignored although mise, ai_clis and ghostty_terminal are selected"
else
  echo "ok: the AI agent launcher follows mise, ai_clis and ghostty_terminal"
fi

if [ -n "$(ignored_launchers kde "$personal_features")" ]; then
  fail "KDE with desktop_apps ignores launchers it should manage"
else
  echo "ok: KDE with desktop_apps manages every launcher"
fi

if ignored_launchers kde '["core_cli"]' | grep -Fxq ".local/share/applications/omarchy-ai-agent.desktop"; then
  echo "ok: the AI agent launcher is left out when ai_clis is not selected"
else
  fail "the AI agent launcher is managed although ai_clis is not selected"
fi

if grep -Eq '^claude = "latest"$' "$repo_root/home/dot_config/mise/conf.d/ai_clis.toml"; then
  echo "ok: the ai_clis tool list installs the claude command the launcher starts"
else
  fail "no feature installs the claude command omarchy-ai-agent.desktop starts"
fi

if [ "$failures" -gt 0 ]; then
  echo "desktop launcher checks failed: $failures" >&2
  exit 1
fi
echo "desktop launcher checks passed"
