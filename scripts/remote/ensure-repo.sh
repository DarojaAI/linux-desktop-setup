#!/bin/bash
set -euo pipefail

# Ensure a target repo is cloned/available on the server
# Usage: bash ensure-repo.sh <owner> <repo>
# Expects VM_GITHUB_TOKEN env var to be set by the calling workflow.

TARGET_OWNER="$1"
TARGET_REPO="$2"

if [ -z "$TARGET_OWNER" ] || [ -z "$TARGET_REPO" ]; then
    echo "ERROR: owner and repo are required"
    exit 1
fi

REPO_DIR="/home/desktopuser/GithubProjects/${TARGET_REPO}"
GH_TOKEN="${VM_GITHUB_TOKEN:-}"

if [ -z "$GH_TOKEN" ]; then
    echo "ERROR: VM_GITHUB_TOKEN is not set"
    exit 1
fi

echo "Checking repo: $TARGET_OWNER/$TARGET_REPO"

if [ -d "$REPO_DIR/.git" ]; then
    echo "Repo already exists at $REPO_DIR - removing and re-cloning to ensure clean state..."
    rm -rf "$REPO_DIR"
fi

if [ -d "$REPO_DIR" ]; then
    echo "Repo directory exists but no .git - removing..."
    rm -rf "$REPO_DIR"
fi

echo "Cloning repo to $REPO_DIR..."
mkdir -p "$(dirname "$REPO_DIR")"
git config --global credential.helper "store"
echo "https://x-access-token:${GH_TOKEN}@github.com" > ~/.git-credentials
git clone "https://github.com/${TARGET_OWNER}/${TARGET_REPO}.git" "$REPO_DIR"

# Set workspace ownership
chown -R desktopuser:desktopuser "$REPO_DIR" 2>/dev/null || true

echo "Repo $TARGET_REPO is ready at $REPO_DIR"