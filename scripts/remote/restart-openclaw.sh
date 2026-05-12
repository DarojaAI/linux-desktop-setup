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

    # Stop first — this also kills any zombie nohup processes holding port 18789
    # (systemd owns the service definition, so it has permission to kill them)
    sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$TARGET_USER")" \
        systemctl --user stop openclaw-gateway.service 2>/dev/null || true
    sleep 2

    # Also kill any stray nohup gateways (belt-and-suspenders)
    pkill -f "openclaw gateway" 2>/dev/null || true
    sleep 1

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

sleep 3
if kill -0 "$GATEWAY_PID" 2>/dev/null; then
    echo "$GATEWAY_PID" > /var/run/openclaw-gateway.pid
    echo "[openclaw-restart] Done (nohup, PID: $GATEWAY_PID)"
else
    echo "[openclaw-restart] ERROR: gateway failed to start"
    exit 1
fi
