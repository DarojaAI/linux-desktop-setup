#!/bin/bash
# Restart OpenClaw gateway — systemd only.
# All deploy targets are established VMs with a running systemd user manager.
# The nohup fallback has been removed because it caused duplicate-process
# races when the systemd-managed process started successfully but the script
# falsely concluded it had failed (is-active doesn't work over SSH).
set -euo pipefail

TARGET_USER="${TARGET_USER:-desktopuser}"

# Verify the unit file exists (created by deploy-desktop.sh / install.sh)
if [[ ! -f "/home/$TARGET_USER/.config/systemd/user/openclaw-gateway.service" ]]; then
    echo "[openclaw-restart] ERROR: systemd unit file not found"
    exit 1
fi

# Stop first — ask openclaw to clean up its own lock files/PID state
sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$TARGET_USER")" \
    openclaw gateway stop 2>/dev/null || true

# Also stop via systemd (belt-and-suspenders)
sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$TARGET_USER")" \
    systemctl --user stop openclaw-gateway.service 2>/dev/null || true

# Kill any stray process by exact name (Node process.title is "openclaw")
pkill -x openclaw 2>/dev/null || true

# Kill anything holding the port
fuser -k 18789/tcp 2>/dev/null || true

# Remove stale lock files
rm -f "/run/user/$(id -u "$TARGET_USER")/openclaw-gateway.pid" 2>/dev/null || true

sleep 2

# Wait for port to be free
for _ in {1..10}; do
    ss -tlnp | grep -q ":18789 " || break
    sleep 1
done

# Reset any previous start-limit-hit state
sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$TARGET_USER")" \
    systemctl --user reset-failed openclaw-gateway.service 2>/dev/null || true

# Restart via systemd
sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$TARGET_USER")" \
    systemctl --user restart openclaw-gateway.service


# Verify by port binding (is-active fails over non-interactive SSH)
# Give extra time for large catalogs (390+ models take ~15-20s to load)
sleep 5
for _ in {1..25}; do
	if ss -tlnp | grep -q ":18789 "; then
		echo "[openclaw-restart] Done (systemd)"
		exit 0
	fi
	sleep 1
done

echo "[openclaw-restart] ERROR: systemd restart did not bind port 18789 within 30s"
