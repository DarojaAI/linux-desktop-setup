#!/bin/bash
set -e

TARGET_OWNER="$1"
TARGET_REPO="$2"
WORKSPACE="/home/desktopuser/GithubProjects/$TARGET_REPO"

if [ ! -d "$WORKSPACE" ]; then
    mkdir -p /home/desktopuser/GithubProjects
    git clone https://x-access-token:$VM_GITHUB_TOKEN@github.com/$TARGET_OWNER/$TARGET_REPO.git "$WORKSPACE"
    chown -R desktopuser:desktopuser "$WORKSPACE"
else
    chown -R desktopuser:desktopuser /home/desktopuser/GithubProjects
    sudo -u desktopuser git -C "$WORKSPACE" config remote.origin.url "https://x-access-token:$VM_GITHUB_TOKEN@github.com/$TARGET_OWNER/$TARGET_REPO.git"
    # Detect the default branch from the remote - use symbolic-ref for reliability
    sudo -u desktopuser git -C "$WORKSPACE" remote set-head origin -a 2>/dev/null || true
    DEFAULT_BRANCH=$(sudo -u desktopuser git -C "$WORKSPACE" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
    if [ -z "$DEFAULT_BRANCH" ]; then
        # Fallback: try ls-remote to get the default branch
        DEFAULT_BRANCH=$(sudo -u desktopuser git -C "$WORKSPACE" ls-remote --symref origin HEAD 2>/dev/null | awk '/^ref:/ { sub(/refs\/heads\//, "", $2); print $2 }')
    fi
    # Final fallback to main/master
    if [ -z "$DEFAULT_BRANCH" ]; then
        if sudo -u desktopuser git -C "$WORKSPACE" rev-parse --verify origin/main >/dev/null 2>&1; then
            DEFAULT_BRANCH="main"
        elif sudo -u desktopuser git -C "$WORKSPACE" rev-parse --verify origin/master >/dev/null 2>&1; then
            DEFAULT_BRANCH="master"
        else
            DEFAULT_BRANCH="main"
        fi
    fi
    echo "Default branch detected: $DEFAULT_BRANCH"
    # Force checkout the correct branch from origin (handles stale tracking configs)
    sudo -u desktopuser git -C "$WORKSPACE" fetch origin "$DEFAULT_BRANCH"
    # Use FETCH_HEAD directly to avoid missing origin/$BRANCH tracking refs
    sudo -u desktopuser git -C "$WORKSPACE" checkout -B "$DEFAULT_BRANCH" "FETCH_HEAD" 2>/dev/null || \
    sudo -u desktopuser git -C "$WORKSPACE" reset --hard "FETCH_HEAD"
    sudo -u desktopuser git -C "$WORKSPACE" clean -fd
fi
echo "Repo ready: $WORKSPACE"
