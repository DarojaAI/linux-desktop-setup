#!/bin/bash
# OpenClaw runtime configuration: config files and systemd override
# Source this from ai-tools.sh

set -euo pipefail

_lib_sh_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../lib.sh
source "$_lib_sh_dir/lib.sh"

validate_openclaw_config() {
    # Validate and auto-fix OpenClaw config — call after any config modification
    local config_file="$1"
    local target_user="$2"
    local user_id
    user_id=$(id -u "$target_user")

    if ! sudo -u "$target_user" XDG_RUNTIME_DIR="/run/user/$user_id" openclaw config validate 2>/dev/null; then
        log_warn "Config invalid after modification, running openclaw doctor --fix"
        sudo -u "$target_user" XDG_RUNTIME_DIR="/run/user/$user_id" openclaw doctor --fix 2>&1 | tail -10
        if sudo -u "$target_user" XDG_RUNTIME_DIR="/run/user/$user_id" openclaw config validate 2>/dev/null; then
            log_info "Config validation passed after doctor --fix"
        else
            log_error "Config still invalid after doctor --fix — manual review needed"
            return 1
        fi
    else
        log_info "Config validation passed"
    fi
    return 0
}

setup_openclaw_config() {
    log_step "Setting up OpenClaw configuration..."

    local target_home
    target_home=$(getent passwd "$TARGET_USER" | cut -d: -f6)
    local openclaw_dir="$target_home/.openclaw"
    local config_file="$openclaw_dir/openclaw.json"

    # Create directory structure
    mkdir -p "$openclaw_dir/agents/main/agent"
    mkdir -p "$openclaw_dir/workspace"
    mkdir -p "$openclaw_dir/skills"

    # Set ownership
    chown -R "$TARGET_USER:$TARGET_USER" "$openclaw_dir" 2>/dev/null || true

    # Config is written by L3 (linux-desktop-seed) via merge-openclaw-config.py
    # Validate existing config if present
    if [[ -f "$config_file" ]]; then
        validate_openclaw_config "$config_file" "$TARGET_USER"
        chmod 644 "$config_file" 2>/dev/null || true
    fi

    log_info "OpenClaw directory structure ready for user $TARGET_USER"
}

setup_openclaw_systemd_override() {
    log_step "Setting up OpenClaw systemd override for API key persistence..."

    local target_home
    target_home=$(getent passwd "$TARGET_USER" | cut -d: -f6)
    local override_dir="$target_home/.config/systemd/user/openclaw-gateway.service.d"
    local override_file="$override_dir/override.conf"

    # API key must come from environment variable
    local api_key="${OPENROUTER_API_KEY:-}"
    if [[ -z "$api_key" ]]; then
        log_error "OPENROUTER_API_KEY environment variable is required"
        return 1
    fi
    local discord_token="${DISCORD_BOT_TOKEN:-}"

    # Get user ID for XDG_RUNTIME_DIR
    local user_id
    user_id=$(id -u "$TARGET_USER")

    mkdir -p "$override_dir"

    cat > "$override_file" << EOF
[Service]
Environment=OPENROUTER_API_KEY=$api_key
Environment=HOME=$target_home
Environment=XDG_RUNTIME_DIR=/run/user/$user_id
EOF

    # Add ANTHROPIC_API_BASE if provided (optional, for OpenRouter proxy)
    local anthropic_base="${ANTHROPIC_API_BASE:-}"
    if [[ -n "$anthropic_base" ]]; then
        echo "Environment=ANTHROPIC_API_BASE=$anthropic_base" >> "$override_file"
    fi

    # Append Discord token if available
    if [[ -n "$discord_token" ]]; then
        echo "Environment=DISCORD_BOT_TOKEN=$discord_token" >> "$override_file"
    fi

    chown -R "$TARGET_USER:$TARGET_USER" "$target_home/.config"

    # Also write the key to ~/.openclaw/.env so the gateway daemon can
    # resolve it via openclaw's env mechanism (auth-profiles.json is not
    # created for non-interactive deployments).
    cat > "$target_home/.openclaw/.env" << EOF
OPENROUTER_API_KEY=$api_key
EOF
    chown "$TARGET_USER:$TARGET_USER" "$target_home/.openclaw/.env"
    chmod 600 "$target_home/.openclaw/.env"
    log_info "OpenClaw env file created at $target_home/.openclaw/.env"

    # Note: daemon-reload and restart happen in setup_openclaw_systemd_service
    # which runs after this function in the deploy order. Writing the override
    # file before the service exists is fine — systemd picks it up on reload.
    log_info "OpenClaw systemd override created at $override_file"
}

setup_openclaw_agent_binding() {
    # Agent binding is now handled by L3 (linux-desktop-seed) after config merge
    # This function is a no-op to maintain backward compatibility with existing callers
    log_info "Agent binding delegated to L3"
    return 0
}

export -f setup_openclaw_config setup_openclaw_systemd_override setup_openclaw_agent_binding validate_openclaw_config
