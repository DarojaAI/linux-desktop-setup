#!/bin/bash
# Configuration module: environment, MCP servers, token rotation, GitHub issues
# Source this from the main deploy script

set -euo pipefail

# Resolve lib.sh from scripts/lib/ (sibling to scripts/deploy/)
_lib_sh_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if [[ -f "${_lib_sh_dir}/lib.sh" ]]; then
    source "${_lib_sh_dir}/lib.sh"
else
    echo "ERROR: Could not find lib.sh in ${_lib_sh_dir}"
    exit 1
fi
unset _lib_sh_dir

# Setup environment
setup_environment() {
    log_step "Setting up environment..."

    local username="desktopuser"
    local user_home=$(getent passwd "$username" | cut -d: -f6)

    if [[ -z "$user_home" ]]; then
        log_error "Cannot find home directory for $username"
        return 1
    fi

    # Create config directory
    local config_dir="$user_home/.config/desktop-seed"
    mkdir -p "$config_dir"

    # Copy environment example if it exists
    local repo_config="$(dirname "$SCRIPT_DIR")/.env.example"
    if [[ -f "$repo_config" ]]; then
        cp "$repo_config" "$config_dir/.env.example"
    fi

    # Create .bashrc additions
    local bashrc_additions="$user_home/.bashrc.desktop-seed"
    cat > "$bashrc_additions" << 'EOF'
# Desktop Seed Environment Configuration

# OpenRouter API (required for Claude Code)
export OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}"

# Claude Code Router configuration
export CCR_CONFIG_PATH="$HOME/.config/claude-code-router.json"

# MCP Servers configuration
export MCP_CONFIG_DIR="$HOME/.config/mcp-servers"

# Desktop Seed configuration
export DESKTOP_SEED_DIR="$HOME/.config/desktop-seed"

# GitHub token for CI/CD operations (loaded from secure file)
if [[ -f ~/.vm-github-token ]]; then
    source ~/.vm-github-token
fi
EOF

    # Write VM_GITHUB_TOKEN to secure file if provided
    if [[ -n "${VM_GITHUB_TOKEN:-}" ]]; then
        log_info "Writing VM_GITHUB_TOKEN to secure file..."
        echo "export VM_GITHUB_TOKEN='$VM_GITHUB_TOKEN'" > "$user_home/.vm-github-token"
        chmod 600 "$user_home/.vm-github-token"
        log_info "  VM_GITHUB_TOKEN written to ~/.vm-github-token"
    fi

    # Add to .bashrc if not already present
    if ! grep -q "desktop-seed" "$user_home/.bashrc" 2>/dev/null; then
        echo "" >> "$user_home/.bashrc"
        echo "# Desktop Seed environment" >> "$user_home/.bashrc"
        echo "if [[ -f ~/.bashrc.desktop-seed ]]; then" >> "$user_home/.bashrc"
        echo "    source ~/.bashrc.desktop-seed" >> "$user_home/.bashrc"
        echo "fi" >> "$user_home/.bashrc"
    fi

    # Set ownership
    chown -R "$username:$username" "$user_home"

    log_info "Environment configured"
}

# Configure MCP servers
configure_mcp_servers() {
    log_step "Configuring MCP servers..."

    local username="desktopuser"
    local user_home=$(getent passwd "$username" | cut -d: -f6)

    if [[ -z "$user_home" ]]; then
        log_error "Cannot find home directory for $username"
        return 1
    fi

    # Create MCP config directory
    local mcp_dir="$user_home/.config"
    mkdir -p "$mcp_dir"

    # Create MCP servers file (empty by default, user adds their own)
    local mcp_file="$mcp_dir/mcp-servers"
    if [[ ! -f "$mcp_file" ]]; then
        touch "$mcp_file"
        log_info "Created MCP servers config (add your servers to $mcp_file)"
    fi

    # Set ownership
    chown "$username:$username" "$mcp_file"

    log_info "MCP servers configured"
}

# Setup token rotation cron
setup_token_rotation_cron() {
    log_step "Setting up token rotation cron..."

    local cron_file="/etc/cron.d/openclaw-token-rotation"

    # Check if token rotation is enabled
    if [[ "${TOKEN_ROTATION_ENABLED:-false}" != "true" ]]; then
        log_info "Token rotation disabled (set TOKEN_ROTATION_ENABLED=true to enable)"
        return 0
    fi

    # Create cron job for token rotation
    cat > "$cron_file" << EOF
# Token rotation for OpenCLAW
# Runs daily at 2 AM
0 2 * * * root /usr/local/bin/rotate-openclaw-tokens.sh >> /var/log/token-rotation.log 2>&1
EOF

    chmod 644 "$cron_file"
    log_info "Token rotation cron configured"
}

# Setup GitHub issues automation
setup_github_issues() {
    log_step "Setting up GitHub issues..."

    local username="desktopuser"
    local user_home=$(getent passwd "$username" | cut -d: -f6)

    if [[ -z "$user_home" ]]; then
        log_error "Cannot find home directory for $username"
        return 1
    fi

    # Create GitHub issues script directory
    local scripts_dir="$user_home/.local/bin"
    mkdir -p "$scripts_dir"

    # Check if GitHub CLI is available
    if ! command -v gh &> /dev/null; then
        log_warn "GitHub CLI not available - skipping GitHub issues setup"
        return 0
    fi

    # Create a simple issue creator script
    cat > "$scripts_dir/create-issue.sh" << 'EOF'
#!/bin/bash
# Create a GitHub issue from the command line

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <title> <body>"
    exit 1
fi

gh issue create --title "$1" --body "$2"
EOF

    chmod +x "$scripts_dir/create-issue.sh"
    chown "$username:$username" "$scripts_dir/create-issue.sh"

    log_info "GitHub issues configured"
}

# Validate deployment
validate_deployment() {
    log_step "Validating deployment..."

    local errors=0

    # Check critical services
    local services=("xrdp" "ssh")
    for svc in "${services[@]}"; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            log_info "Service $svc: running"
        else
            log_warn "Service $svc: not running"
            ((errors++))
        fi
    done

    # Check critical commands (chromium/gcloud are optional due to apt repo issues)
    local required_commands=("code" "claude" "gh")
    for cmd in "${required_commands[@]}"; do
        if command -v "$cmd" &> /dev/null; then
            log_info "Command $cmd: installed"
        else
            log_warn "Command $cmd: not found"
            ((errors++))
        fi
    done

    # Check optional commands (warn but don't fail)
    local optional_commands=("chromium" "gcloud" "terraform")
    for cmd in "${optional_commands[@]}"; do
        if command -v "$cmd" &> /dev/null; then
            log_info "Command $cmd: installed"
        else
            log_warn "Command $cmd: not found (optional)"
        fi
    done

    if [[ $errors -eq 0 ]]; then
        log_info "Deployment validation passed"
    else
        log_warn "Deployment validation: $errors issues found"
    fi

    return $errors
}

# Show deployment summary
show_summary() {
    log_step "Deployment Complete!"

    echo ""
    echo "========================================="
    echo "  Remote Desktop Deployed Successfully"
    echo "========================================="
    echo ""
    echo "Access:"
    echo "  - RDP: <SERVER_IP>:3389"
    echo "  - Username: desktopuser"
    echo "  - Password: desktop"
    echo ""
    echo "Installed Tools:"
    echo "  - GNOME Desktop"
    echo "  - xrdp (RDP server)"
    echo "  - Visual Studio Code"
    echo "  - Claude Code"
    echo "  - OpenRouter CLI"
    echo "  - Claude Code Router"
    echo "  - Chromium Browser"
    echo "  - GitHub CLI"
    echo "  - Bun runtime"
    echo "  - OpenCLAW"
    echo "  - Terraform & Terragrunt"
    echo "  - Google Cloud SDK"
    echo ""
    echo "Next Steps:"
    echo "  1. Connect via RDP"
    echo "  2. Set your API keys in ~/.config/desktop-seed/.env"
    echo "  3. Run: source ~/.bashrc"
    echo ""
}

# Configure X11 wrapper
configure_xwrapper() {
    log_step "Configuring X11 wrapper..."

    # Configure X11 to allow any user to start X servers
    if [[ ! -f /etc/X11/Xwrapper.config ]] || ! grep -q "allowed_users" /etc/X11/Xwrapper.config; then
        echo "allowed_users=any" > /etc/X11/Xwrapper.config
        echo "allowed_users=console" >> /etc/X11/Xwrapper.config
        log_info "Configured X11 wrapper for multi-user access"
    fi

    # Configure D-Bus to allow system-wide connections
    if [[ ! -f /etc/dbus-1/system.d/xrdp.conf ]]; then
        mkdir -p /etc/dbus-1/system.d
        cat > /etc/dbus-1/system.d/xrdp.conf << 'EOF'
<!DOCTYPE busconfig PUBLIC
 "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <policy user="root">
    <allow own="org.freedesktop.Notifications"/>
  </policy>
  <policy context="default">
    <allow send_destination="org.freedesktop.Notifications"/>
    <allow receive_sender="org.freedesktop.Notifications"/>
  </policy>
</busconfig>
EOF
        log_info "Configured D-Bus for notifications"
    fi
}

# Configure Claude Code with OpenRouter
configure_claude_openrouter() {
    log_step "Configuring Claude Code with OpenRouter..."

    # Create Claude config directory
    local claude_dir="$HOME/.config/claude"
    mkdir -p "$claude_dir"

    # Create or update settings
    local settings_file="$claude_dir/settings.json"
    if [[ -f "$settings_file" ]]; then
        log_info "Claude settings already exist"
    else
        cat > "$settings_file" << 'EOF'
{
  "apiKey": "OPENROUTER_API_KEY",
  "model": "openrouter/minimax/MiniMax-M2.7"
}
EOF
        log_info "Created Claude settings with OpenRouter"
    fi

    # Add to .bashrc for persistence
    if ! grep -q "OPENROUTER_API_KEY" "$HOME/.bashrc" 2>/dev/null; then
        echo 'export OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}"' >> "$HOME/.bashrc"
    fi

    log_info "Claude OpenRouter configuration complete"
}

# Export functions for use in main script
export -f setup_environment configure_mcp_servers configure_xwrapper configure_claude_openrouter setup_token_rotation_cron
export -f setup_github_issues validate_deployment show_summary