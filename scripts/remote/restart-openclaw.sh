#!/bin/bash
# Restart OpenClaw gateway — handles both systemd and nohup fallback
# Called from deploy-desktop.sh or GitHub Actions workflow

set -euo pipefail

TARGET_USER="${TARGET_USER:-desktopuser}"
OVERRIDE_DIR="/home/$TARGET_USER/.config/systemd/user/openclaw-gateway.service.d"
OVERRIDE_FILE="$OVERRIDE_DIR/override.conf"
LOG_FILE="${LOG_FILE:-/var/log/openclaw-gateway.log}"

# Try systemd first (works on established VMs with active user session)
if sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$TARGET_USER")" \
    systemctl --user list-units --type=service 2>/dev/null | grep -q openclaw-gateway; then
    echo "[openclaw-restart] Restarting via systemd..."
    sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$TARGET_USER")" \
        systemctl --user restart openclaw-gateway.service
    echo "[openclaw-restart] Done (systemd)"
    exit 0
fi

# Fallback: direct nohup restart
# Needed when systemd user manager isn't accessible over SSH
echo "[openclaw-restart] systemd unavailable, restarting via nohup..."

pkill -f "openclaw gateway" 2>/dev/null || true
sleep 2

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

sleep 2
if kill -0 "$GATEWAY_PID" 2>/dev/null; then
    echo "$GATEWAY_PID" > /var/run/openclaw-gateway.pid
    echo "[openclaw-restart] Done (nohup, PID: $GATEWAY_PID)"
else
    echo "[openclaw-restart] ERROR: gateway failed to start"
    exit 1
fi
