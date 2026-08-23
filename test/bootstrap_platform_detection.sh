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

eval "$(extract_function resolve_distro_family)"
eval "$(extract_function is_nobara)"
eval "$(extract_function detect_platform)"

# The variables below are consumed by the bootstrap functions eval'd above.
# shellcheck disable=SC2034
OS="Linux"
DISTRO=""
DISTRO_LIKE=""
DISTRO_PLATFORM_ID=""
DISTRO_IMAGE_BASED=""
DISTRO_FAMILY=""

set_os_release() {
  DISTRO="$1"
  # shellcheck disable=SC2034
  DISTRO_LIKE="$2"
  # shellcheck disable=SC2034
  DISTRO_PLATFORM_ID="$3"
}

expect_platform() {
  local id="$1" id_like="$2" platform_id="$3" expected_family="$4" expected_platform="$5"
  local family platform

  set_os_release "$id" "$id_like" "$platform_id"
  family="$(resolve_distro_family)"
  if [ "$family" != "$expected_family" ]; then
    echo "expected ID=$id ID_LIKE='$id_like' PLATFORM_ID='$platform_id' to resolve to family '$expected_family', got '$family'"
    exit 1
  fi

  # shellcheck disable=SC2034
  DISTRO_FAMILY="$family"
  platform="$(detect_platform 2>/dev/null)" || {
    echo "expected ID=$id ID_LIKE='$id_like' PLATFORM_ID='$platform_id' to map to platform '$expected_platform', but detection failed"
    exit 1
  }
  if [ "$platform" != "$expected_platform" ]; then
    echo "expected ID=$id ID_LIKE='$id_like' PLATFORM_ID='$platform_id' to map to platform '$expected_platform', got '$platform'"
    exit 1
  fi
}

expect_unsupported() {
  local id="$1" id_like="$2" platform_id="$3"
  local message

  set_os_release "$id" "$id_like" "$platform_id"
  # shellcheck disable=SC2034
  DISTRO_FAMILY="$(resolve_distro_family)"
  if message="$(detect_platform 2>&1)"; then
    echo "expected ID=$id ID_LIKE='$id_like' PLATFORM_ID='$platform_id' to be rejected, got platform '$message'"
    exit 1
  fi
  case "$message" in
    *"Unsupported Linux distro: $id"*)
      ;;
    *)
      echo "expected rejection of ID=$id to name the real distro id, got: $message"
      exit 1
      ;;
  esac
}

# Supported distros keep their own family and platform.
expect_platform ubuntu "debian" "" ubuntu ubuntu
expect_platform fedora "" "platform:f44" fedora fedora
expect_platform arch "" "" arch arch
expect_platform manjaro "arch" "" arch arch

# Fedora rebuilds follow ID_LIKE onto the Fedora path (Nobara, Ultramarine).
expect_platform nobara "rhel centos fedora" "platform:f44" fedora fedora
expect_platform ultramarine "fedora" "platform:f42" fedora fedora

# Arch derivatives follow ID_LIKE onto the Arch path.
expect_platform endeavouros "arch" "" arch arch

# Enterprise Linux lists fedora in ID_LIKE but is not a Fedora rebuild.
expect_unsupported rhel "fedora" "platform:el9"
expect_unsupported almalinux "rhel centos fedora" "platform:el9"
expect_unsupported rocky "rhel centos fedora" "platform:el9"
expect_unsupported centos "rhel fedora" "platform:el10"
expect_unsupported unknown-fedora-like "fedora" ""

# Distros outside the supported families fail early and name the real id.
expect_unsupported debian "" ""
expect_unsupported linuxmint "ubuntu debian" ""
expect_unsupported opensuse-tumbleweed "opensuse suse" ""

# Image-based (ostree/bootc) systems are rejected even when their os-release
# identity would otherwise map onto the Fedora path.
for image_id in fedora bazzite bluefin; do
  set_os_release "$image_id" "fedora" "platform:f42"
  # shellcheck disable=SC2034
  DISTRO_FAMILY="$(resolve_distro_family)"
  DISTRO_IMAGE_BASED=1
  if message="$(detect_platform 2>&1)"; then
    echo "expected image-based ID=$image_id to be rejected, got platform '$message'"
    exit 1
  fi
  case "$message" in
    *"Unsupported image-based Linux"*"$image_id"*)
      ;;
    *)
      echo "expected rejection of image-based ID=$image_id to explain why, got: $message"
      exit 1
      ;;
  esac
  # shellcheck disable=SC2034
  DISTRO_IMAGE_BASED=""
done

# Nobara-specific handling triggers only on the real Nobara id.
DISTRO="nobara"
if ! is_nobara; then
  echo "expected is_nobara to detect ID=nobara"
  exit 1
fi
# shellcheck disable=SC2034
DISTRO="fedora"
if is_nobara; then
  echo "expected is_nobara to be false for ID=fedora"
  exit 1
fi

echo "bootstrap platform detection passed"
