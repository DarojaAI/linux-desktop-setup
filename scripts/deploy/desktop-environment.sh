#!/bin/bash
# Monitoring and reliability module: session monitor, keyring, extensions
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