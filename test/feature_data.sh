#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! python3 -c 'import yaml' >/dev/null 2>&1; then
  echo "python3 with PyYAML not found, skipping feature data checks."
  exit 0
fi

python3 - "$repo_root" <<'PY'
import glob, os, sys, yaml

root = sys.argv[1]
failures = []

def load(path):
    with open(path) as handle:
        return yaml.safe_load(handle)

def flatten(package_sets):
    return {feature: sorted(name for names in installers.values() for name in names) for feature, installers in package_sets.items()}

# A file with `overrides: <platform>` is not a platform of its own: on a
# derivative such as Omarchy its features replace the base platform's entries.
platform_sets = {}
overrides = []
for path in sorted(glob.glob(os.path.join(root, "ansible/vars/package_sets/*.yml"))):
    data = load(path)
    if "overrides" in data:
        overrides.append((path, data))
        continue
    platform_sets[data["platform"]] = flatten(data["package_sets"])

for path, data in overrides:
    name = os.path.splitext(os.path.basename(path))[0]
    base = data["overrides"]
    if base not in platform_sets:
        failures.append(f"{name}.yml overrides '{base}', which is not a platform package set")
        continue
    if "platform" in data or "package_family" in data:
        failures.append(f"{name}.yml declares a platform; an override file only replaces entries of {base}.yml")
    merged = dict(platform_sets[base])
    for feature, packages in flatten(data["package_sets"]).items():
        if feature not in platform_sets[base]:
            failures.append(f"{name}.yml replaces '{feature}', which {base}.yml does not implement; a derivative cannot add features")
        merged[feature] = packages
    platform_sets[f"{base} ({name})"] = merged

windows = load(os.path.join(root, "home/.chezmoidata/packages.yaml"))["windows_package_sets"]
platform_sets["windows"] = {feature: sorted(installers["winget"]) for feature, installers in windows.items()}

aliases = {
    "git": {"git", "Git.Git"},
    "neovim": {"neovim", "Neovim.Neovim"},
    "ripgrep": {"ripgrep", "BurntSushi.ripgrep.MSVC"},
    "fzf": {"fzf", "junegunn.fzf"},
    "jq": {"jq", "jqlang.jq"},
    "gh": {"gh", "github-cli", "GitHub.cli"},
}
for platform, sets in platform_sets.items():
    core = set(sets.get("core_cli", []))
    for tool, names in aliases.items():
        if not core & names:
            failures.append(f"{platform}: core_cli does not provide {tool}; a feature must mean the same capability on every platform")
        for feature, packages in sets.items():
            if tool in ("fzf", "gh") and feature != "core_cli" and set(packages) & names:
                failures.append(f"{platform}: {tool} belongs to core_cli but is listed under {feature}")

profiles = {}
for path in sorted(glob.glob(os.path.join(root, "ansible/vars/profiles/*.yml"))):
    data = load(path)
    profiles[data["profile_name"]] = data["features"]

known = set(os.listdir(os.path.join(root, "ansible/roles/features")))
known |= {os.path.splitext(name)[0] for name in os.listdir(os.path.join(root, "home/dot_config/mise/conf.d"))}
for platform, sets in platform_sets.items():
    if platform != "windows":
        known |= set(sets)

for key in windows:
    if key in profiles or key == "common":
        failures.append(f"packages.yaml: '{key}' is a profile name; Windows packages are keyed by feature")
    elif key not in known:
        failures.append(f"packages.yaml: '{key}' is not a feature any other platform implements")

for profile, features in profiles.items():
    selected = sorted({package for feature in features for package in platform_sets["windows"].get(feature, [])})
    if not selected:
        failures.append(f"profile {profile} selects no Windows packages")
    without_docker = [feature for feature in features if feature != "docker_desktop"]
    leaked = [package for feature in without_docker for package in platform_sets["windows"].get(feature, []) if "Docker" in package]
    if leaked:
        failures.append(f"profile {profile} would install {leaked} on Windows without selecting docker_desktop")
    print(f"ok: profile {profile} selects {len(selected)} winget packages through its features")

for failure in failures:
    print(f"FAIL: {failure}", file=sys.stderr)
if failures:
    sys.exit(1)
print("feature data checks passed")
PY
