#!/bin/bash
# AI tools module: OpenCLAW, OpenRouter
# Source this from the main deploy script

set -euo pipefail

if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# Resolve openclaw scripts relative to this file (sibling to this file in scripts/deploy/openclaw/)
_ai_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# OpenCLAW is optional — source only if not disabled
if [[ "${LOAD_OPENCLAW:-true}" != "false" ]]; then
    # shellcheck source=openclaw/install.sh
    source "$_ai_dir/openclaw/install.sh"
    # shellcheck source=openclaw/config.sh
    source "$_ai_dir/openclaw/config.sh"
    # shellcheck source=openclaw/governance.sh
    source "$_ai_dir/openclaw/governance.sh"
fi

# Run OpenClaw channel health check on a remote VM
# Usage: run_openclaw_channel_check <prod|test|head> [guild_id]
run_openclaw_channel_check() {
    local target_vm="${1:-}"
    local guild_id="${2:-1485047825967480862}"

    if [[ -z "$target_vm" ]]; then
        log_error "Usage: run_openclaw_channel_check <prod|test|head> [guild_id]"
        return 1
    fi

    log_info "Running OpenClaw channel health check on $target_vm..."

    if ssh -o ConnectTimeout=10 "$target_vm" \
        "bash /home/\$USER/maintenance-scripts/check-openclaw-channels.sh $target_vm $guild_id" 2>/dev/null; then
        log_info "Channel health check: PASS"
        return 0
    else
        local exit_code=$?
        log_error "Channel health check: FAIL (exit code $exit_code)"
        return $exit_code
    fi
}

unset _ai_dir
