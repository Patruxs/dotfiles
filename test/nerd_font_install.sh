#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() {
  echo "$1"
  exit 1
}

install="$REPO_ROOT/scripts/nerd-font-install.sh"
export HOME="$work/home"
export XDG_DATA_HOME="$work/home/.local/share"
unset GITHUB_TOKEN
mkdir -p "$HOME" "$work/bin" "$work/http"
export PATH="$work/bin:$PATH"
export DOTFILES_GITHUB_API="https://api.github.com"
export FAKE_FC_LIST="$work/fc-list.out"
: >"$FAKE_FC_LIST"
: >"$work/downloads.log"

cat >"$work/bin/curl" <<EOF
#!/usr/bin/env bash
set -euo pipefail
root="$work/http"
out=""
url=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    -o) out="\$2"; shift 2 ;;
    -H|--max-time|--retry|--retry-delay) shift 2 ;;
    -*) shift ;;
    *) url="\$1"; shift ;;
  esac
done
echo "\$url" >>"$work/downloads.log"
path="\$root/\${url#https://}"
[ -f "\$path" ] || { echo "fake curl: no fixture for \$url" >&2; exit 22; }
if [ -n "\$out" ]; then cp "\$path" "\$out"; else cat "\$path"; fi
EOF
chmod +x "$work/bin/curl"

cat >"$work/bin/fc-list" <<'EOF'
#!/usr/bin/env bash
cat "$FAKE_FC_LIST"
EOF
cat >"$work/bin/fc-cache" <<'EOF'
#!/usr/bin/env bash
echo "$@" >>"${FAKE_FC_LIST%.out}.cache"
EOF
chmod +x "$work/bin/fc-list" "$work/bin/fc-cache"

publish_release() {
  local version="$1" src="$work/src/fonts"
  rm -rf "$src"
  mkdir -p "$src" "$work/http/github.com/ryanoasis/nerd-fonts/releases/download/v$version" "$work/http/api.github.com/repos/ryanoasis/nerd-fonts/releases"
  for style in Regular Bold Italic; do
    printf 'font %s %s\n' "$style" "$version" >"$src/JetBrainsMonoNerdFont-$style.ttf"
  done
  echo "readme" >"$src/README.md"
  tar -cJf "$work/http/github.com/ryanoasis/nerd-fonts/releases/download/v$version/JetBrainsMono.tar.xz" -C "$src" .
  cat >"$work/http/api.github.com/repos/ryanoasis/nerd-fonts/releases/latest" <<EOF
{"tag_name":"v$version","assets":[{"name":"JetBrainsMono.zip","browser_download_url":"https:\/\/github.com\/ryanoasis\/nerd-fonts\/releases\/download\/v$version\/JetBrainsMono.zip"},{"name":"JetBrainsMono.tar.xz","browser_download_url":"https:\/\/github.com\/ryanoasis\/nerd-fonts\/releases\/download\/v$version\/JetBrainsMono.tar.xz"}]}
EOF
}

publish_release 3.5.1

if "$install" check >"$work/check1.out" 2>&1; then
  fail "check must fail when the font is missing"
fi
grep -q '^JetBrainsMono Nerd Font: missing (latest 3.5.1)$' "$work/check1.out" || fail "missing font not reported: $(cat "$work/check1.out")"

"$install" install >"$work/install1.out" 2>&1 || fail "install failed: $(cat "$work/install1.out")"
grep -q '^JetBrainsMono Nerd Font: installed 3.5.1$' "$work/install1.out" || fail "install not reported: $(cat "$work/install1.out")"
font_dir="$XDG_DATA_HOME/fonts/JetBrainsMonoNerdFont"
[ "$(find "$font_dir" -name '*.ttf' | wc -l)" -eq 3 ] || fail "the font files were not installed"
[ ! -e "$font_dir/README.md" ] || fail "only .ttf files must be installed"
[ "$(cat "$font_dir/.version")" = "3.5.1" ] || fail "the version marker was not written"
grep -q "$font_dir" "$work/fc-list.cache" || fail "the font cache was not refreshed for the new directory"
grep -q 'JetBrainsMono.tar.xz$' "$work/downloads.log" || fail "the tar.xz asset must be chosen"
grep -q 'JetBrainsMono.zip$' "$work/downloads.log" && fail "the zip asset must not be downloaded"

"$install" check >"$work/check2.out" 2>&1 || fail "check must pass after install: $(cat "$work/check2.out")"
grep -q '^JetBrainsMono Nerd Font: up to date (3.5.1)$' "$work/check2.out" || fail "up-to-date font not reported: $(cat "$work/check2.out")"
"$install" install >"$work/install2.out" 2>&1 || fail "second install failed: $(cat "$work/install2.out")"
grep -q '^JetBrainsMono Nerd Font: unchanged (3.5.1)$' "$work/install2.out" || fail "second install must change nothing: $(cat "$work/install2.out")"

publish_release 3.6.0
if "$install" check >"$work/check3.out" 2>&1; then
  fail "check must fail when upstream moved ahead"
fi
grep -q '^JetBrainsMono Nerd Font: update available (3.5.1 -> 3.6.0)$' "$work/check3.out" || fail "update not detected: $(cat "$work/check3.out")"
"$install" install >"$work/install3.out" 2>&1 || fail "update failed: $(cat "$work/install3.out")"
grep -q '^JetBrainsMono Nerd Font: updated 3.5.1 -> 3.6.0$' "$work/install3.out" || fail "update not reported: $(cat "$work/install3.out")"
grep -q '3.6.0' "$font_dir/JetBrainsMonoNerdFont-Regular.ttf" || fail "the font files were not replaced"

: >"$work/downloads.log"
printf '/usr/share/fonts/nerd-fonts/JetBrainsMono/JetBrainsMonoNerdFont-Regular.ttf: JetBrainsMono Nerd Font,JetBrainsMono NF\n' >"$FAKE_FC_LIST"
"$install" check >"$work/check4.out" 2>&1 || fail "check must pass when a system package provides the font: $(cat "$work/check4.out")"
grep -q 'system package' "$work/check4.out" || fail "system package not reported: $(cat "$work/check4.out")"
"$install" install >"$work/install4.out" 2>&1 || fail "install must succeed with a system package: $(cat "$work/install4.out")"
grep -q 'unchanged (system package)' "$work/install4.out" || fail "install must leave a system package alone: $(cat "$work/install4.out")"
[ ! -s "$work/downloads.log" ] || fail "nothing must be downloaded when a system package provides the font"

printf '%s/fonts/JetBrainsMonoNerdFont/JetBrainsMonoNerdFont-Regular.ttf: JetBrainsMono Nerd Font,JetBrainsMono NF\n' "$XDG_DATA_HOME" >"$FAKE_FC_LIST"
"$install" check >"$work/check5.out" 2>&1 || fail "check must pass for the user copy: $(cat "$work/check5.out")"
grep -q 'up to date (3.6.0)' "$work/check5.out" || fail "the user copy must not count as a system package: $(cat "$work/check5.out")"

if "$install" >/dev/null 2>&1; then
  fail "running without a subcommand must fail"
fi

echo "nerd font install passed"
