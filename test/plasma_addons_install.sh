#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() {
  echo "$1"
  exit 1
}

install="$REPO_ROOT/scripts/plasma-addons-install.sh"
export HOME="$work/home"
export XDG_DATA_HOME="$work/home/.local/share"
unset DBUS_SESSION_BUS_ADDRESS GITHUB_TOKEN
mkdir -p "$HOME" "$work/bin" "$work/http"
export PATH="$work/bin:$PATH"
export DOTFILES_GITHUB_API="https://api.github.com"
export DOTFILES_GITHUB_WEB="https://github.com"
export DOTFILES_GITHUB_RAW="https://raw.githubusercontent.com"
export DOTFILES_KDE_STORE_API="https://api.kde-look.org/ocs/v1"

cat >"$work/bin/curl" <<EOF
#!/usr/bin/env bash
set -euo pipefail
root="$work/http"
out=""
url=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    -o) out="\$2"; shift 2 ;;
    -H) shift 2 ;;
    --max-time) shift 2 ;;
    -*) shift ;;
    *) url="\$1"; shift ;;
  esac
done
path="\$root/\${url#https://}"
[ -f "\$path" ] || { echo "fake curl: no fixture for \$url" >&2; exit 22; }
if [ -n "\$out" ]; then cp "\$path" "\$out"; else cat "\$path"; fi
EOF
chmod +x "$work/bin/curl"

cat >"$work/bin/kpackagetool6" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
type=""
source=""
for arg in "$@"; do
  case "$arg" in
    --type=*) type="${arg#--type=}" ;;
    --install|--upgrade) ;;
    *) source="$arg" ;;
  esac
done
case "$type" in
  KWin/Script) target="$XDG_DATA_HOME/kwin/scripts" ;;
  KWin/Effect) target="$XDG_DATA_HOME/kwin/effects" ;;
  Plasma/Applet) target="$XDG_DATA_HOME/plasma/plasmoids" ;;
  *) echo "fake kpackagetool6: unexpected type $type" >&2; exit 1 ;;
esac
if [ -d "$source" ]; then
  package="$source"
else
  unpacked="$(mktemp -d)"
  tar -xf "$source" -C "$unpacked"
  package="$(dirname "$(find "$unpacked" -name metadata.json -print -quit)")"
fi
id="$(sed -n 's/^[[:space:]]*"Id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$package/metadata.json" | head -n 1)"
mkdir -p "$target"
rm -rf "${target:?}/$id"
cp -R "$package" "$target/$id"
EOF
chmod +x "$work/bin/kpackagetool6"

make_package() {
  local dir="$1" id="$2" version="$3"
  mkdir -p "$dir/contents/code"
  printf '{\n    "KPlugin": {\n        "Id": "%s",\n        "Version": "%s"\n    }\n}\n' "$id" "$version" >"$dir/metadata.json"
  echo "// $id $version" >"$dir/contents/code/main.js"
}

publish_krohnkite() {
  local version="$1" src="$work/src/krohnkite"
  rm -rf "$src"
  make_package "$src/krohnkite" krohnkite "$version"
  mkdir -p "$work/http/github.com/anametologin/krohnkite/releases/download/$version" \
    "$work/http/api.github.com/repos/anametologin/krohnkite/releases"
  tar -czf "$work/http/github.com/anametologin/krohnkite/releases/download/$version/krohnkite.kwinscript" -C "$src" krohnkite
  cat >"$work/http/api.github.com/repos/anametologin/krohnkite/releases/latest" <<EOF
{
  "tag_name": "$version",
  "assets": [
    {
      "name": "krohnkite.kwinscript",
      "browser_download_url": "https://github.com/anametologin/krohnkite/releases/download/$version/krohnkite.kwinscript"
    }
  ]
}
EOF
}

publish_geometry_change() {
  local version="$1" src="$work/src/geometry_change"
  rm -rf "$src"
  make_package "$src/kwin4_effect_geometry_change" kwin4_effect_geometry_change "$version"
  mkdir -p "$work/http/github.com/peterfajdiga/kwin4_effect_geometry_change/releases/download/v$version" \
    "$work/http/api.github.com/repos/peterfajdiga/kwin4_effect_geometry_change/releases"
  tar -czf "$work/http/github.com/peterfajdiga/kwin4_effect_geometry_change/releases/download/v$version/effect.tar.gz" -C "$src" kwin4_effect_geometry_change
  cat >"$work/http/api.github.com/repos/peterfajdiga/kwin4_effect_geometry_change/releases/latest" <<EOF
{
  "tag_name": "v$version",
  "assets": [
    {
      "name": "kwin4_effect_geometry_change_${version//./_}.tar.gz",
      "browser_download_url": "https://github.com/peterfajdiga/kwin4_effect_geometry_change/releases/download/v$version/effect.tar.gz"
    }
  ]
}
EOF
}

publish_active_accent_frame() {
  local version="$1" src="$work/src/decorations"
  rm -rf "$src"
  mkdir -p "$src/Plasma-window-decorations-main/ActiveAccentFrame" "$src/Plasma-window-decorations-main/ActiveAccentDark"
  printf '[Desktop Entry]\nName=Active Accent Frame\nX-KDE-PluginInfo-Name=ActiveAccentFrame\nX-KDE-PluginInfo-Version=%s\n' "$version" \
    >"$src/Plasma-window-decorations-main/ActiveAccentFrame/metadata.desktop"
  echo "<svg/>" >"$src/Plasma-window-decorations-main/ActiveAccentFrame/decoration.svg"
  printf '[Desktop Entry]\nX-KDE-PluginInfo-Version=%s\n' "$version" >"$src/Plasma-window-decorations-main/ActiveAccentDark/metadata.desktop"
  mkdir -p "$work/http/github.com/nclarius/Plasma-window-decorations/archive" \
    "$work/http/raw.githubusercontent.com/nclarius/Plasma-window-decorations/HEAD/ActiveAccentFrame"
  tar -czf "$work/http/github.com/nclarius/Plasma-window-decorations/archive/HEAD.tar.gz" -C "$src" Plasma-window-decorations-main
  cp "$src/Plasma-window-decorations-main/ActiveAccentFrame/metadata.desktop" \
    "$work/http/raw.githubusercontent.com/nclarius/Plasma-window-decorations/HEAD/ActiveAccentFrame/metadata.desktop"
}

publish_kde_control_station() {
  local store_version="$1" package_version="$2" src="$work/src/kde_control_station"
  rm -rf "$src"
  make_package "$src/KdeControlStation" KdeControlStation "$package_version"
  mkdir -p "$work/http/files.pling.com/download" "$work/http/api.kde-look.org/ocs/v1/content/data"
  tar -cJf "$work/http/files.pling.com/download/KdeControlStation.tar.xz" -C "$src" KdeControlStation
  printf '{"status":"ok","data":[{"id":"2196105","name":"KDE Control Station","version":"0.0.0","downloadlink1":"https:\\/\\/files.pling.com\\/download\\/KdeControlStation.tar.xz","downloadname1":"KdeControlStation.tar.xz","download_version1":"%s"}]}\n' "$store_version" \
    >"$work/http/api.kde-look.org/ocs/v1/content/data/2196105?format=json"
}

publish_krohnkite 0.9.9.2
publish_geometry_change 1.5
publish_active_accent_frame 9.0
publish_kde_control_station 2.14.1 2.11.0

if "$install" check >"$work/check1.out" 2>&1; then
  fail "check must fail when no add-on is installed"
fi
[ "$(grep -c ': missing (latest ' "$work/check1.out")" -eq 4 ] || fail "check must report every add-on as missing: $(cat "$work/check1.out")"

"$install" install >"$work/install1.out" 2>&1 || fail "install failed: $(cat "$work/install1.out")"
grep -q '^krohnkite: installed 0.9.9.2$' "$work/install1.out" || fail "krohnkite install not reported: $(cat "$work/install1.out")"
grep -q '^geometry_change: installed 1.5$' "$work/install1.out" || fail "geometry_change install not reported: $(cat "$work/install1.out")"
grep -q '^active_accent_frame: installed 9.0$' "$work/install1.out" || fail "active_accent_frame install not reported: $(cat "$work/install1.out")"
grep -q '^kde_control_station: installed 2.14.1$' "$work/install1.out" || fail "kde_control_station install not reported: $(cat "$work/install1.out")"
[ -f "$XDG_DATA_HOME/plasma/plasmoids/KdeControlStation/contents/code/main.js" ] || fail "KDE Control Station was not installed as a Plasma applet"
[ "$(cat "$XDG_DATA_HOME/plasma/plasmoids/KdeControlStation/.store-version")" = "2.14.1" ] || fail "KDE Control Station store version marker not written"
[ -f "$XDG_DATA_HOME/kwin/scripts/krohnkite/contents/code/main.js" ] || fail "krohnkite was not installed as a KWin script"
[ -f "$XDG_DATA_HOME/kwin/effects/kwin4_effect_geometry_change/contents/code/main.js" ] || fail "geometry change was not installed as a KWin effect"
[ -f "$XDG_DATA_HOME/aurorae/themes/ActiveAccentFrame/decoration.svg" ] || fail "ActiveAccentFrame was not installed as an Aurorae theme"
[ ! -e "$XDG_DATA_HOME/aurorae/themes/ActiveAccentDark" ] || fail "only the ActiveAccentFrame flavour must be installed"

"$install" check >"$work/check2.out" 2>&1 || fail "check must pass after install: $(cat "$work/check2.out")"
[ "$(grep -c ': up to date (' "$work/check2.out")" -eq 4 ] || fail "check must report every add-on as up to date: $(cat "$work/check2.out")"

"$install" install >"$work/install2.out" 2>&1 || fail "second install failed: $(cat "$work/install2.out")"
[ "$(grep -c ': unchanged (' "$work/install2.out")" -eq 4 ] || fail "second install must change nothing: $(cat "$work/install2.out")"
grep -q '^all add-ons up to date$' "$work/install2.out" || fail "second install must say nothing changed: $(cat "$work/install2.out")"

publish_active_accent_frame 9.1
publish_krohnkite 0.9.9.3
publish_kde_control_station 2.15.0 2.12.0

if "$install" check >"$work/check3.out" 2>&1; then
  fail "check must fail when upstream moved ahead"
fi
grep -q '^krohnkite: update available (0.9.9.2 -> 0.9.9.3)$' "$work/check3.out" || fail "krohnkite update not detected: $(cat "$work/check3.out")"
grep -q '^active_accent_frame: update available (9.0 -> 9.1)$' "$work/check3.out" || fail "active_accent_frame update not detected: $(cat "$work/check3.out")"
grep -q '^geometry_change: up to date (1.5)$' "$work/check3.out" || fail "geometry_change must stay up to date: $(cat "$work/check3.out")"
grep -q '^kde_control_station: update available (2.14.1 -> 2.15.0)$' "$work/check3.out" || fail "kde_control_station update not detected: $(cat "$work/check3.out")"

"$install" install >"$work/install3.out" 2>&1 || fail "update install failed: $(cat "$work/install3.out")"
grep -q '^krohnkite: updated 0.9.9.2 -> 0.9.9.3$' "$work/install3.out" || fail "krohnkite update not reported: $(cat "$work/install3.out")"
grep -q '^active_accent_frame: updated 9.0 -> 9.1$' "$work/install3.out" || fail "active_accent_frame update not reported: $(cat "$work/install3.out")"
grep -q '^geometry_change: unchanged (1.5)$' "$work/install3.out" || fail "geometry_change must be left alone: $(cat "$work/install3.out")"
grep -q '^3 add-on(s) changed$' "$work/install3.out" || fail "update count wrong: $(cat "$work/install3.out")"
grep -q '"Version": "2.12.0"' "$XDG_DATA_HOME/plasma/plasmoids/KdeControlStation/metadata.json" || fail "KDE Control Station was not upgraded"
grep -q 'X-KDE-PluginInfo-Version=9.1' "$XDG_DATA_HOME/aurorae/themes/ActiveAccentFrame/metadata.desktop" || fail "ActiveAccentFrame was not replaced with the newer copy"
grep -q '"Version": "0.9.9.3"' "$XDG_DATA_HOME/kwin/scripts/krohnkite/metadata.json" || fail "krohnkite was not upgraded"

"$install" check >"$work/check4.out" 2>&1 || fail "check must pass after update: $(cat "$work/check4.out")"

if "$install" >/dev/null 2>&1; then
  fail "running without a subcommand must fail"
fi

echo "plasma add-ons install passed"
