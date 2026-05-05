#!/bin/bash
set -e

TARGET_REPO="$1"
CHANNEL_ID="$2"
CONFIG_FILE="/home/desktopuser/.openclaw/openclaw.json"

sudo -u desktopuser XDG_RUNTIME_DIR=/run/user/1000 openclaw agents add \
    "$TARGET_REPO" \
    --workspace "/home/desktopuser/GithubProjects/$TARGET_REPO" || true

# Bind via direct JSON edit - CLI generates deprecated accountId format
# Use jq to insert correct peer format binding
sudo -u desktopuser jq --arg agent "$TARGET_REPO" --arg channel "$CHANNEL_ID" \
    '.bindings = [(.bindings // [])
      | map(select(.agentId != $agent or (.match // {}).channel != "discord"))
      | . + [{"type": "route", "agentId": $agent,
               "match": {"channel": "discord",
                         "peer": {"kind": "channel", "id": $channel}}]' \
    "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"

echo "OpenClaw binding applied: $TARGET_REPO -> $CHANNEL_ID (peer format)"
