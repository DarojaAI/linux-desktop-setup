#!/bin/bash
set -euo pipefail

# Remote Linux Desktop Deployment Script - Modular Version
# Deploys: GNOME, xrdp, VS Code, Claude Code, Chromium, OpenRouter
# Target: Ubuntu 20.04/22.04/24.04

SCRIPT_VERSION="2.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
LOG_FILE="/tmp/deploy-desktop-$(date +%Y%m%d-%H%M%S).log"
TARGET_USER="desktopuser"

# Trim whitespace from all GitHub-sourced environment variables
# GitHub UI may add trailing spaces to variable values
for var in OPENROUTER_API_KEY DISCORD_BOT_TOKEN OPENCLAW_DISCORD_CHANNEL_ID \
           OPENCLAW_DISCORD_ALLOWED_USER OPENCLAW_DISCORD_GUILD_ID VM_GITHUB_TOKEN \
           ANTHROPIC_API_BASE; do
    if [[ -n "${!var:-}" ]]; then
        declare "$var=$(echo "${!var}" | xargs)"
    fi
done

# Dry run mode - preview what would be installed without actually installing
DRY_RUN=false
for arg in "$@"; do
    case "$arg" in
        --dry-run|--preview)
            DRY_RUN=true
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run, --preview  Show what would be installed without installing"
            echo "  --help, -h            Show this help message"
            echo "  SKIP_OPENCLAW_VALIDATION=true  Skip OpenClaw pre/post checks"
            echo ""
            exit 0
            ;;
    esac
done

# Source all modules
source "$SCRIPT_DIR/scripts/deploy/lib.sh"
source "$SCRIPT_DIR/scripts/deploy/system.sh"
source "$SCRIPT_DIR/scripts/deploy/dev-tools.sh"
source "$SCRIPT_DIR/scripts/deploy/ai-tools.sh"
source "$SCRIPT_DIR/scripts/deploy/desktop-environment.sh"
source "$SCRIPT_DIR/scripts/deploy/monitoring.sh"
source "$SCRIPT_DIR/scripts/deploy/configure.sh"

# Main function
main() {
    # Handle dry-run mode
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "========================================="
        echo "  DRY RUN MODE - No changes will be made"
        echo "========================================="
        echo ""
        log_info "This would install the following components:"
        log_info "  - GNOME Desktop"
        log_info "  - xrdp (RDP server)"
        log_info "  - Visual Studio Code"
        log_info "  - Claude Code"
        log_info "  - OpenRouter CLI"
        log_info "  - Claude Code Router"
        log_info "  - Chromium Browser"
        log_info "  - GitHub CLI"
        log_info "  - Bun runtime"
        log_info "  - OpenCLAW"
        log_info "  - Terraform & Terragrunt"
        log_info "  - Google Cloud SDK"
        log_info "  - Session monitoring"
        log_info "  - GNOME extensions"
        log_info "  - VM maintenance scripts"
        echo ""
        log_info "To run this deployment:"
        log_info "  sudo bash deploy-desktop.sh"
        echo ""
        exit 0
    fi

    # Opt-out flags: set SKIP_<GROUP>=true to disable a category
    # e.g. sudo SKIP_AI_TOOLS=true bash deploy-desktop.sh
    : "${SKIP_SYSTEM:=false}"  "${SKIP_DEV_TOOLS:=false}"  "${SKIP_AI_TOOLS:=false}"
    : "${SKIP_CONFIG:=false}"  "${SKIP_MONITORING:=false}"  "${SKIP_OPTIONAL:=false}"

    log_info "Starting Remote Desktop Deployment v$SCRIPT_VERSION"
    log_info "Log file: $LOG_FILE"

    # Validate critical configuration
    validate_deployment_config

    check_root
    detect_ubuntu_version

    # System setup
    if [[ "${SKIP_SYSTEM:-false}" != "true" ]]; then
        update_system
        install_gnome
        configure_xwrapper
        install_xrdp
        create_desktop_user
        copy_desktop_configs
    fi

    # Development tools
    if [[ "${SKIP_DEV_TOOLS:-false}" != "true" ]]; then
        install_vscode
        install_claude_code
        install_claude_skills
        configure_claude_openrouter
        install_openrouter
        install_claude_code_router
        install_chromium
        install_ghcli
        install_bun
        install_terraform
        install_gcloud
    fi

    # Pre-flight validation for OpenClaw
    if [[ "${SKIP_OPENCLAW_VALIDATION:-false}" != "true" ]]; then
        validate_openclaw_deployment
    fi

    # AI tools (OpenCLAW, OpenRouter)
    if [[ "${SKIP_AI_TOOLS:-false}" != "true" ]]; then
        install_openclaw
        setup_openclaw_wrapper
        setup_openclaw_config
        setup_openclaw_agent_binding
        setup_openclaw_lock_config
        setup_openclaw_validate_config
        setup_openclaw_backup_config
        setup_openclaw_change_request
        setup_openclaw_systemd_override
        setup_openclaw_systemd_service
    fi

    # Post-deploy validation
    if [[ "${SKIP_OPENCLAW_VALIDATION:-false}" != "true" ]]; then
        local smoke_test="$SCRIPT_DIR/tests/smoke-openclaw.sh"
        if [[ -f "$smoke_test" ]]; then
            log_info "Running post-deploy smoke test..."
            bash "$smoke_test" || log_warn "Smoke test had failures"
        fi
    fi

    # Configuration
    if [[ "${SKIP_CONFIG:-false}" != "true" ]]; then
        setup_environment
        configure_mcp_servers
        create_desktop_shortcuts
    fi

    # Monitoring & reliability
    if [[ "${SKIP_MONITORING:-false}" != "true" ]]; then
        setup_keyring
        setup_monitoring
        setup_gnome_extensions
    fi

    # Optional features
    if [[ "${SKIP_OPTIONAL:-false}" != "true" ]]; then
        setup_token_rotation_cron
        setup_github_issues
    fi

    # VM Maintenance Scripts (for head VM controlling other VMs)
    install_maintenance_scripts

    # Validation
    validate_deployment
    show_summary

    log_info "System ready for deployment"
}

# Install maintenance scripts for VM-A head node
install_maintenance_scripts() {
    log_info "Installing VM maintenance scripts..."

    local scripts_dir="$SCRIPT_DIR/scripts/maintenance"
    local target_dir="/home/$TARGET_USER/maintenance-scripts"

    if [[ ! -d "$scripts_dir" ]]; then
        log_warn "Maintenance scripts directory not found: $scripts_dir"
        return 0
    fi

    # Create target directory
    if ! mkdir -p "$target_dir" 2>/dev/null; then
        log_error "Failed to create maintenance scripts directory: $target_dir"
        return 1
    fi

    # Copy all maintenance scripts with validation
    local scripts_copied=0
    for script in "$scripts_dir"/*.sh; do
        if [[ -f "$script" ]]; then
            local script_name
            script_name=$(basename "$script")

            # Validate script syntax before copying
            if bash -n "$script" 2>/dev/null; then
                if cp "$script" "$target_dir/" && chmod +x "$target_dir/$script_name"; then
                    log_info "  Installed: $script_name"
                    scripts_copied=$((scripts_copied + 1))
                else
                    log_warn "  Failed to copy: $script_name"
                fi
            else
                log_warn "  Skipped (syntax error): $script_name"
            fi
        fi
    done

    if [[ $scripts_copied -eq 0 ]]; then
        log_warn "No maintenance scripts were installed"
    else
        # Set ownership
        chown -R "$TARGET_USER:$TARGET_USER" "$target_dir" 2>/dev/null || \
            log_warn "Could not change ownership of maintenance scripts"

        log_info "Installed $scripts_copied maintenance script(s)"
    fi

    # Setup SSH config for maintenance access to other VMs
    setup_ssh_config

    log_info "Maintenance scripts installation complete"
}

# Validate deployment configuration before starting
validate_deployment_config() {
    log_info "Validating deployment configuration..."
    local errors=0

    # Validate TARGET_USER
    if [[ -z "$TARGET_USER" ]]; then
        log_error "TARGET_USER is not set"
        errors=$((errors + 1))
    elif ! id "$TARGET_USER" &>/dev/null; then
        # Will be created later, but warn if definitely missing
        log_warn "TARGET_USER '$TARGET_USER' does not exist yet (will be created)"
    fi

    # Validate SCRIPT_DIR
    if [[ -z "$SCRIPT_DIR" ]]; then
        log_error "SCRIPT_DIR is not set"
        errors=$((errors + 1))
    elif [[ ! -d "$SCRIPT_DIR" ]]; then
        log_error "SCRIPT_DIR does not exist: $SCRIPT_DIR"
        errors=$((errors + 1))
    fi

    # Validate LOG_FILE path is writable
    if [[ -n "$LOG_FILE" ]]; then
        local log_dir
        log_dir=$(dirname "$LOG_FILE")
        if [[ ! -d "$log_dir" ]] && ! mkdir -p "$log_dir" 2>/dev/null; then
            log_error "Cannot create log directory: $log_dir"
            errors=$((errors + 1))
        fi
    fi

    if [[ $errors -gt 0 ]]; then
        log_error "Deployment configuration has $errors error(s)"
        exit 1
    fi

    log_info "Configuration validation passed"
}

setup_ssh_config() {
    log_info "Setting up SSH config for maintenance access..."

    # Write SSH private key from environment to root's .ssh if provided
    if [[ -n "${SSH_PRIVATE_KEY:-}" ]]; then
        log_info "Writing SSH private key from environment..."
        mkdir -p /root/.ssh
        chmod 700 /root/.ssh
        echo "$SSH_PRIVATE_KEY" > /root/.ssh/id_ed25519
        chmod 600 /root/.ssh/id_ed25519
        log_info "  SSH private key written to /root/.ssh/id_ed25519"
    fi

    local ssh_dir="/home/$TARGET_USER/.ssh"
    local config_file="$ssh_dir/config"

    # Create .ssh directory if it doesn't exist
    mkdir -p "$ssh_dir"
    chown "$TARGET_USER:$TARGET_USER" "$ssh_dir"
    chmod 700 "$ssh_dir"

    # Add SSH config entries for known VMs (if not already present)
    if [[ ! -f "$config_file" ]]; then
        touch "$config_file"
        chown "$TARGET_USER:$TARGET_USER" "$config_file"
        chmod 600 "$config_file"
    fi

    # Add prod config if not exists
    if ! grep -q "^Host prod$" "$config_file" 2>/dev/null; then
        cat >> "$config_file" << 'EOF'

Host prod
    HostName 204.168.182.32
    User root
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new
    ServerAliveInterval 60
EOF
        log_info "  Added SSH config for prod"
    fi

    # Add test config if not exists
    if ! grep -q "^Host test$" "$config_file" 2>/dev/null; then
        cat >> "$config_file" << 'EOF'

Host test
    HostName 95.217.10.37
    User root
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new
    ServerAliveInterval 60
EOF
        log_info "  Added SSH config for test"
    fi

    # Copy root's SSH key to desktopuser if it exists and desktopuser doesn't have one
    if [[ -f "/root/.ssh/id_ed25519" ]]; then
        if [[ -f "$ssh_dir/id_ed25519" ]]; then
            log_info "  SSH key already exists for desktopuser"
        else
            if cp /root/.ssh/id_ed25519 "$ssh_dir/id_ed25519" 2>/dev/null; then
                chown "$TARGET_USER:$TARGET_USER" "$ssh_dir/id_ed25519"
                chmod 600 "$ssh_dir/id_ed25519"
                log_info "  Copied SSH key to desktopuser"
            else
                log_warn "  Could not copy SSH key to desktopuser"
            fi
        fi
    else
        log_warn "  No SSH key found at /root/.ssh/id_ed25519"
    fi

    # Copy root's known_hosts if desktopuser doesn't have one
    if [[ -f "/root/.ssh/known_hosts" ]]; then
        if cp /root/.ssh/known_hosts "$ssh_dir/known_hosts" 2>/dev/null; then
            chown "$TARGET_USER:$TARGET_USER" "$ssh_dir/known_hosts"
            chmod 600 "$ssh_dir/known_hosts"
            log_info "  Copied known_hosts to desktopuser"
        else
            log_warn "  Could not copy known_hosts to desktopuser"
        fi
    fi

    # Validate SSH config
    log_info "Validating SSH configuration..."
    local ssh_errors=0

    if [[ ! -d "$ssh_dir" ]]; then
        log_error "  SSH directory not created: $ssh_dir"
        ssh_errors=$((ssh_errors + 1))
    fi

    if [[ ! -f "$ssh_dir/config" ]]; then
        log_error "  SSH config file not created: $ssh_dir/config"
        ssh_errors=$((ssh_errors + 1))
    fi

    if [[ ! -f "$ssh_dir/id_ed25519" ]]; then
        log_warn "  No SSH private key for desktopuser"
    fi

    if [[ $ssh_errors -gt 0 ]]; then
        log_error "SSH config setup had $ssh_errors errors"
    else
        log_info "SSH config setup complete and validated"
    fi
}

main "$@"
