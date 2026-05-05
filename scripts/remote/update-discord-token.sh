#!/bin/bash
set -e

OVERRIDE_FILE="/home/desktopuser/.config/systemd/user/openclaw-gateway.service.d/override.conf"
if [ -f "$OVERRIDE_FILE" ]; then
    sed -i '/^Environment=DISCORD_BOT_TOKEN=/d' "$OVERRIDE_FILE"
    echo "Environment=DISCORD_BOT_TOKEN=$DISCORD_BOT_TOKEN" >> "$OVERRIDE_FILE"
    chown desktopuser:desktopuser "$OVERRIDE_FILE"
    echo "Updated Discord token in $OVERRIDE_FILE"
else
    echo "ERROR: override.conf not found at $OVERRIDE_FILE"
    exit 1
fi
