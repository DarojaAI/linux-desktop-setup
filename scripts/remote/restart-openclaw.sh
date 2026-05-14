#!/bin/bash
# Restart OpenClaw gateway — handles both systemd and nohup fallback
# Called from deploy-desktop.sh or GitHub Actions workflow

set -euo pipefail

TARGET_USER="${TARGET_USER:-desktopuser}"
OVERRIDE_DIR="/home/$TARGET_USER/.config/systemd/user/openclaw-gateway.service.d"
OVERRIDE_FILE="$OVERRIDE_DIR/override.conf"
LOG_FILE="${LOG_FILE:-/var/log/openclaw-gateway.log}"

# Try systemd first (works on established VMs with active user session)
# Use list-unit-files (not list-units) because list-units only shows ACTIVE units;
# a stopped/inactive service won't match and we'll incorrectly fall through to nohup.
if sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$TARGET_USER")" \
    systemctl --user list-unit-files --type=service 2>/dev/null | grep -q openclaw-gateway; then
    echo "[openclaw-restart] Restarting via systemd..."

    # Stop first — ask openclaw to clean up its own lock files/PID state
    # (systemd stop alone doesn't remove openclaw's internal runtime locks)
    sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$TARGET_USER")" \
        openclaw gateway stop 2>/dev/null || true

    sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$TARGET_USER")" \
        systemctl --user stop openclaw-gateway.service 2>/dev/null || true
    sleep 2

    # Belt-and-suspenders: also kill any stray process by exact name
    # and by port. Node process.title is "openclaw", not "openclaw gateway",
    # so -x (exact match) works; -f would match this script and kill itself.
    pkill -x openclaw 2>/dev/null || true
    fuser -k 18789/tcp 2>/dev/null || true

    # Remove any stale openclaw lock files under the user runtime dir
    rm -f "/run/user/$(id -u "$TARGET_USER")/openclaw-gateway.pid" 2>/dev/null || true

    sleep 2

    # Wait for port to be free before restarting
    for _ in {1..10}; do
        ss -tlnp | grep -q ":18789 " || break
        sleep 1
    done

    sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$TARGET_USER")" \
        systemctl --user restart openclaw-gateway.service

    sleep 3

    # Verify systemd actually started it — check active state, not just exit code
    if sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$TARGET_USER")" \
        systemctl --user is-active openclaw-gateway.service 2>/dev/null; then
        echo "[openclaw-restart] Done (systemd)"
        exit 0
    fi

    echo "[openclaw-restart] systemd restart reported success but service not active — falling back to nohup"
fi

# Fallback: direct nohup restart
# Needed when systemd user manager isn't accessible over SSH
echo "[openclaw-restart] systemd unavailable or failed, restarting via nohup..."

# Ask openclaw to clean up its own locks before we take over via nohup
sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$TARGET_USER")" \
    openclaw gateway stop 2>/dev/null || true

# Kill by exact process name (safer than -f which matches this script)
pkill -x openclaw 2>/dev/null || true
fuser -k 18789/tcp 2>/dev/null || true

# Remove stale lock files
rm -f "/run/user/$(id -u "$TARGET_USER")/openclaw-gateway.pid" 2>/dev/null || true

sleep 2

# Wait for port to be free before restarting
for _ in {1..10}; do
    ss -tlnp | grep -q ":18789 " || break
    sleep 1
done
# Read tokens from the override file written by deploy-desktop.sh
if [[ -f "$OVERRIDE_FILE" ]]; then
    while IFS= read -r line; do
        [[ "$line" =~ ^Environment=([^=]+)=(.+)$ ]] && \
            export "${BASH_REMATCH[1]}=${BASH_REMATCH[2]}"
    done < "$OVERRIDE_FILE"
fi

sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$TARGET_USER")" \
    nohup openclaw gateway --port 18789 >> "$LOG_FILE" 2>&1 &
GATEWAY_PID=$!

sleep 3
if kill -0 "$GATEWAY_PID" 2>/dev/null; then
    echo "$GATEWAY_PID" > /var/run/openclaw-gateway.pid
    echo "[openclaw-restart] Done (nohup, PID: $GATEWAY_PID)"
else
    echo "[openclaw-restart] ERROR: gateway failed to start"
    exit 1
fi
