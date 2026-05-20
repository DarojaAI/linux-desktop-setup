#!/bin/bash
set -euo pipefail

# Add an OpenClaw agent and binding for a target repo on the server
# Usage: bash configure-openclaw-agent.sh <repo_name> <discord_channel_id>
#
# This script creates a workspace directory, agent directory, and binds the
# agent to a specific Discord channel so it only responds in that channel.

TARGET_REPO="$1"
DISCORD_CHANNEL_ID="$2"

if [ -z "$TARGET_REPO" ] || [ -z "$DISCORD_CHANNEL_ID" ]; then
    echo "ERROR: repo name and Discord channel ID are required"
    exit 1
fi

# Only allow alphanumeric and hyphens/underscores for safety
if ! [[ "$TARGET_REPO" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "ERROR: invalid repo name '$TARGET_REPO'"
    exit 1
fi

OPENCLAW_DIR="/home/desktopuser/.openclaw"
AGENTS_DIR="$OPENCLAW_DIR/agents"
WORKSPACE_DIR="/home/desktopuser/GithubProjects/${TARGET_REPO}"
AGENT_DIR="$AGENTS_DIR/${TARGET_REPO}/agent"
CONFIG_FILE="$OPENCLAW_DIR/openclaw.json"
GATEWAY_TOKEN="${GATEWAY_TOKEN:-}"

echo "Configuring OpenClaw agent for repo: $TARGET_REPO"
echo "Discord channel: $DISCORD_CHANNEL_ID"

# Unlock config for writing
# Use 666 so desktopuser (the owner) can write even when running via sudo -u desktopuser
chmod 666 "$CONFIG_FILE" 2>/dev/null || true

# Verify the file is actually writable by desktopuser (not root — root always succeeds)
echo "Verifying desktopuser write access to $CONFIG_FILE..."
if ! sudo -u desktopuser test -w "$CONFIG_FILE" 2>/dev/null; then
    echo "ERROR: Config file is not writable by desktopuser after chmod. Check permissions on server."
    exit 1
fi
echo "Unlock verified — desktopuser can write to $CONFIG_FILE"

# Create required directories
mkdir -p "$WORKSPACE_DIR"
mkdir -p "$(dirname "$AGENT_DIR")"
mkdir -p "$AGENTS_DIR"

# Set ownership so gateway can read agent files
chown -R desktopuser:desktopuser "$WORKSPACE_DIR"
chown -R desktopuser:desktopuser "$AGENTS_DIR"
# Ensure workspace exists and has basic files
if [ ! -f "$WORKSPACE_DIR/IDENTITY.md" ]; then
    echo "Creating IDENTITY.md for $TARGET_REPO..."
    cat > "$WORKSPACE_DIR/IDENTITY.md" << AGENT_IDENTITY
# IDENTITY.md - $TARGET_REPO Agent

- **Name:** ${TARGET_REPO}
- **Creature:** Agent
- **Vibe:** Direct, competent, no-fluff. Gets things done.
- **Emoji:** 🤖

## Role
- Repo: $TARGET_REPO
- Bound to channel: $DISCORD_CHANNEL_ID

---
_Managed by linux-desktop-seed deployment._
AGENT_IDENTITY
fi

# Agent metadata file
AGENT_METADATA_FILE="$AGENT_DIR/agent.json"
mkdir -p "$AGENT_DIR"
cat > "$AGENT_METADATA_FILE" << AGENT_META
{
  "id": "${TARGET_REPO}",
  "name": "${TARGET_REPO}",
  "workspace": "${WORKSPACE_DIR}",
  "agentDir": "${AGENT_DIR}"
}
AGENT_META

# Create minimal SKILL.md in agent directory
if [ ! -f "$AGENT_DIR/SKILL.md" ]; then
    cat > "$AGENT_DIR/SKILL.md" << SKILL_META
# Agent: ${TARGET_REPO}

Managed by linux-desktop-seed via openclaw-bind-repos.sh.
SKILL_META
fi

# Add or update agent and binding in openclaw.json using Python
python3 << PYTHON_SCRIPT
import json
import sys

config_file = "$CONFIG_FILE"
repo_name = "$TARGET_REPO"
channel_id = "$DISCORD_CHANNEL_ID"

# Load existing config
with open(config_file, 'r') as f:
    config = json.load(f)

# Ensure agents.list exists
if 'agents' not in config:
    config['agents'] = {}
if 'list' not in config['agents']:
    config['agents']['list'] = []

# Remove any existing agent with same id
config['agents']['list'] = [a for a in config['agents']['list'] if a.get('id') != repo_name]

# Add new agent
agent = {
    "id": repo_name,
    "name": repo_name,
    "workspace": "$WORKSPACE_DIR",
    "agentDir": "$AGENT_DIR"
}
config['agents']['list'].append(agent)

# Ensure bindings list exists
if 'bindings' not in config:
    config['bindings'] = []

# Remove any existing binding for this channel (same agentId + channel combo)
config['bindings'] = [
    b for b in config['bindings']
    if not (b.get('agentId') == repo_name and
            b.get('match', {}).get('peer', {}).get('id') == channel_id)
]

# Add new binding
binding = {
    "type": "route",
    "agentId": repo_name,
    "match": {
        "channel": "discord",
        "peer": {
            "kind": "channel",
            "id": channel_id
        }
    }
}
config['bindings'].append(binding)

# Write back
with open(config_file, 'w') as f:
    json.dump(config, f, indent=2)

print(f"Agent '{repo_name}' and binding to channel '{channel_id}' added successfully")
PYTHON_SCRIPT

# Re-lock config
chown -R desktopuser:desktopuser "$AGENTS_DIR/${TARGET_REPO}" 2>/dev/null || true
chown -R desktopuser:desktopuser "$WORKSPACE_DIR" 2>/dev/null || true
chmod 444 "$CONFIG_FILE" 2>/dev/null || true

echo "Agent and binding for $TARGET_REPO configured successfully"
