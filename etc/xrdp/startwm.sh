#!/bin/bash
# xrdp GNOME session script - start gnome-shell directly for xrdp compatibility
# This script is called by sesman to start the desktop session

set -euo pipefail

# Defensive profile loading (handles unbound variables in some profile scripts)
set +u
[ -r /etc/profile ] && . /etc/profile 2>/dev/null || true
[ -r "$HOME/.profile" ] && . "$HOME/.profile" 2>/dev/null || true
set -u

echo "=== Starting RDP session at $(date) ===" >> ~/.xsession-errors

# Wait for X server (Xvnc) to be ready
_display_num="${DISPLAY#*:}"
for i in {1..30}; do
    [ -S "/tmp/.X11-unix/X${_display_num}" ] && break
    sleep 0.5
done
unset _display_num

[ -z "$DISPLAY" ] && { echo "ERROR: DISPLAY not set" >&2; exit 1; }

# Environment - CRITICAL: force X11, not Wayland (Xvnc doesn't support Wayland)
export GDK_BACKEND=x11
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=GNOME
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export GNOME_SHELL_SESSION_MODE=ubuntu
export GNOME_SHELL_WAYLANDRESTART=false

echo "DISPLAY=$DISPLAY, GDK_BACKEND=$GDK_BACKEND" >> ~/.xsession-errors

# Start D-Bus session if not already running
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    eval $(dbus-launch --sh-syntax)
fi
echo "DBUS=$DBUS_SESSION_BUS_ADDRESS" >> ~/.xsession-errors

# Note: DPI/scaling must be configured AFTER gnome-shell starts, not before
# User can manually run: gsettings set org.gnome.desktop.interface text-scaling-factor 1.5
# Or configure via GNOME Settings → Accessibility → Text Size

# Start gnome-shell directly (bypasses gnome-session which has issues with xrdp)
exec nohup gnome-shell >> ~/.xsession-errors 2>&1
