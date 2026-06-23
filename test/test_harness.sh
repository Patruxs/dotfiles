#!/usr/bin/env bash
set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err() { echo -e "${RED}[ERROR]${NC} $1"; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "=== Dotfiles Test Harness ==="

# 1. Dependency Checks
if ! command -v chezmoi >/dev/null 2>&1; then
    log_err "chezmoi is required but not installed."
    exit 1
fi

if ! command -v shellcheck >/dev/null 2>&1; then
    log_warn "shellcheck is not installed. Skipping bash linting."
else
    log_info "Running ShellCheck on shell scripts..."
    # Find scripts but exclude templates (.tmpl)
    find . -type f -name "*.sh" -not -path "*/.git/*" | xargs shellcheck || {
        log_err "ShellCheck failed."
        exit 1
    }
    log_info "ShellCheck passed."
fi

if ! command -v ansible-playbook >/dev/null 2>&1; then
    log_warn "ansible-playbook is not installed. Skipping Ansible syntax check."
else
    log_info "Running Ansible Syntax Check..."
    ansible-playbook --syntax-check ansible/playbooks/setup.yml || {
        log_err "Ansible syntax check failed."
        exit 1
    }
    log_info "Ansible syntax check passed."
fi

log_info "Running bootstrap sudo detection regression test..."
./test/bootstrap_sudo_detection.sh || {
    log_err "Bootstrap sudo detection regression test failed."
    exit 1
}
log_info "Bootstrap sudo detection regression test passed."

log_info "Running CI bootstrap regression checks..."
./test/ci_bootstrap_regressions.sh || {
    log_err "CI bootstrap regression checks failed."
    exit 1
}
log_info "CI bootstrap regression checks passed."

# 2. Chezmoi Dry Run
log_info "Running Chezmoi Dry Run (verifies templates render without errors)..."
tmpdir="$(mktemp -d)"
cleanup_tmpdir() {
    rm -rf "$tmpdir"
}
trap cleanup_tmpdir EXIT

mkdir -p "$tmpdir/home" "$tmpdir/cache"

chezmoi apply \
    --dry-run \
    --force \
    --no-tty \
    --mode symlink \
    --source "$REPO_ROOT" \
    --destination "$tmpdir/home" \
    --cache "$tmpdir/cache" \
    --persistent-state "$tmpdir/chezmoi-state.boltdb" \
    --override-data '{"git":{"name":"CI User","email":"ci@example.com"}}' || {
    log_err "Chezmoi dry run failed. Check template syntax."
    exit 1
}
log_info "Chezmoi dry run passed."

# 3. Idempotency Check (Optional)
if [ "${1:-}" == "--idempotent" ]; then
    log_info "Running Full Idempotency Check (requires sudo)..."
    ./bootstrap.sh --profile personal > /tmp/dotfiles_run1.log 2>&1
    log_info "First run complete. Running again to check for changes..."
    ./bootstrap.sh --profile personal > /tmp/dotfiles_run2.log 2>&1
    
    if grep -qE "changed=[1-9]" /tmp/dotfiles_run2.log; then
        log_err "Idempotency test failed. Changes were detected on the second run."
        exit 1
    else
        log_info "Idempotency test passed. No changes on second run."
    fi
else
    log_info "Skipping Idempotency test. Use '--idempotent' to run."
fi

log_info "All fast tests completed successfully!"
