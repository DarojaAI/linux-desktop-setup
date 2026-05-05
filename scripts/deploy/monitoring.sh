#!/bin/bash
# Monitoring and reliability module: session monitor, keyring, extensions
# Source this from the main deploy script

set -euo pipefail

# Import common library
# SCRIPT_DIR is inherited from the main script
# If not set, detect it
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
# Resolve lib.sh path relative to THIS script (not inherited SCRIPT_DIR)
_lib_sh_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if [[ -f "$_lib_sh_dir/lib.sh" ]]; then
    source "$_lib_sh_dir/lib.sh"
else
    echo "ERROR: Could not find lib.sh in $_lib_sh_dir"
    exit 1
fi
unset _lib_sh_dir

# Create desktop shortcuts
create_desktop_shortcuts() {
    log_step "Creating desktop shortcuts..."

    local username="desktopuser"
    local user_home=$(getent passwd "$username" | cut -d: -f6)
    local desktop_dir="$user_home/Desktop"

    if [[ -z "$user_home" ]]; then
        log_error "Cannot find home directory for $username"
        return 1
    fi

    # Create Desktop directory if it doesn't exist
    mkdir -p "$desktop_dir"

    # Create VS Code shortcut
    cat > "$desktop_dir/VS Code.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Visual Studio Code
Comment=Code Editor
Exec=code
Icon=code
Terminal=false
Categories=Development;IDE;
EOF

    # Create Chromium shortcut
    cat > "$desktop_dir/Chromium.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Chromium
Comment=Web Browser
Exec=chromium-browser
Icon=chromium-browser
Terminal=false
Categories=Network;WebBrowser;
EOF

    # Create Terminal shortcut
    cat > "$desktop_dir/Terminal.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Terminal
Comment=Terminal Emulator
Exec=gnome-terminal
Icon=gnome-terminal
Terminal=false
Categories=System;TerminalEmulator;
EOF

    # Set ownership
    chown -R "$username:$username" "$desktop_dir"

    log_info "Desktop shortcuts created"
}

# Setup GNOME Keyring
setup_keyring() {
    log_step "Setting up GNOME Keyring..."

    local username="desktopuser"
    local user_home=$(getent passwd "$username" | cut -d: -f6)

    if [[ -z "$user_home" ]]; then
        log_error "Cannot find home directory for $username"
        return 1
    fi

    # Ensure keyring directory exists
    mkdir -p "$user_home/.local/share/keyrings"
    mkdir -p "$user_home/.local/share/gnome-online-accounts"

    # Set ownership
    chown -R "$username:$username" "$user_home/.local"

    log_info "GNOME Keyring directories created"
}

# Setup session monitoring
setup_monitoring() {
    log_step "Setting up session monitoring..."

    local username="desktopuser"
    local user_home=$(getent passwd "$username" | cut -d: -f6)

    if [[ -z "$user_home" ]]; then
        log_error "Cannot find home directory for $username"
        return 1
    fi

    # Copy monitoring script
    local monitor_script="/usr/local/bin/session-monitor.sh"
    local repo_script="$SCRIPT_DIR/scripts/session-monitor.sh"

    if [[ -f "$repo_script" ]]; then
        # Convert CRLF to LF for Linux compatibility
        sed 's/\r$//' "$repo_script" > "$monitor_script"
        chmod +x "$monitor_script"
        log_info "Installed session monitor script"
    else
        log_warn "Session monitor script not found in repo"
        return 1
    fi

    # Copy analysis script
    local analyze_script="/usr/local/bin/analyze-session-logs.sh"
    local repo_analyze="$SCRIPT_DIR/scripts/analyze-session-logs.sh"

    if [[ -f "$repo_analyze" ]]; then
        # Convert CRLF to LF for Linux compatibility
        sed 's/\r$//' "$repo_analyze" > "$analyze_script"
        chmod +x "$analyze_script"
        log_info "Installed session analysis script"
    fi

    # Create config file before enabling service
    local config_dir="/var/lib/xrdp"
    mkdir -p "$config_dir"
    cat > "$config_dir/session-monitor-config.sh" << 'EOF'
# Session Monitor Configuration
MEMORY_THRESHOLD=80
CPU_THRESHOLD=75
CHECK_INTERVAL=30
LOG_FILE="/var/log/xrdp/session-monitor.log"
ALERT_LOG="/var/log/xrdp/session-alerts.log"
EOF

    # Create log directory
    mkdir -p /var/log/xrdp
    touch /var/log/xrdp/session-monitor.log
    touch /var/log/xrdp/session-alerts.log

    # Install the monitoring service using the script's built-in installer
    log_info "Installing session monitor service..."
    if "$monitor_script" --enable 2>&1; then
        log_info "Session monitoring service installed"
    else
        log_warn "Failed to install session monitoring service"
    fi

    log_info "Session monitoring configured"
}

# Setup GNOME extensions
setup_gnome_extensions() {
    log_step "Setting up GNOME extensions..."

    # Install GNOME extension manager
    if ! command -v gnome-extensions &> /dev/null; then
        apt-get install -y gnome-shell-extensions 2>/dev/null || true
    fi

    # Install specific extensions
    local extensions=(
        "https://extensions.gnome.org/extension/1267/cascade-windows/"
    )

    # Note: Extension installation would require browser automation
    # For now, just log that it would need manual enabling
    log_info "GNOME extensions available (manual enable required)"

    # Create desktop shortcuts for extension settings
    local username="desktopuser"
    local user_home=$(getent passwd "$username" | cut -d: -f6)

    if [[ -n "$user_home" ]]; then
        cat > "$user_home/Desktop/Extensions.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=GNOME Extensions
Comment=Manage GNOME Shell Extensions
Exec=gnome-extensions-app
Icon=gnome-extensions
Terminal=false
Categories=System;Settings;
EOF
        chown "$username:$username" "$user_home/Desktop/Extensions.desktop"
    fi

    log_info "GNOME extensions setup complete"
}

# Export functions for use in main script
export -f create_desktop_shortcuts setup_keyring setup_monitoring setup_gnome_extensions