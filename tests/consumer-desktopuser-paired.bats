#!/usr/bin/env bats
# Consumer-side contract test for linux-desktop-setup paired with
# linux-headless-setup#46 (the L2 hardening ship).
#
# Pre-condition (set by headless's user.sh):
#   - desktopuser exists with a real home
#   - /home/desktopuser/.ssh/authorized_keys is populated from
#     /root/.ssh/authorized_keys (the post-#46 copy)
#   - /etc/sudoers.d/desktopuser contains the bounded allowlist
#
# These tests do NOT mutate state. They assert what the desktop-side
# scripts can rely on, complementing tests/security-ssh-access-mode-
# idempotent.bats on the headless side.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

@test "scripts reference desktopuser as the default SSH target user" {
    # Pre-#46 mirror work should treat desktopuser as the deploy chain
    # identity. Loose check: presence of TARGET_USER=desktopuser default
    # in scripts/, not a hard allowlist.
    grep -qE 'TARGET_USER[=:][[:space:]]*"?desktopuser"?' \
        "$REPO_ROOT/scripts/remote/"*.sh 2>/dev/null
}

@test "system.sh handles desktopuser existence idempotently" {
    grep -qE 'id +-u +desktopuser' "$REPO_ROOT/scripts/deploy/system.sh"
}

@test "configure-openclaw-agent.sh chowns ~/.openclaw to desktopuser" {
    grep -qE 'chown[[:space:]]+-R[[:space:]]+desktopuser:desktopuser' \
        "$REPO_ROOT/scripts/remote/configure-openclaw-agent.sh"
}

@test "no deploy script defaults to SSH as root without justification" {
    # Mirror PR #1464 pattern: every root@-use should be either allowlisted
    # (systemctl/chpasswd/install-X) or paired with a desktopuser alternative.
    hits="$(grep -nE 'ssh[[:space:]]+(.*[^A-Za-z])root@' \
        "$REPO_ROOT/scripts/"*.sh "$REPO_ROOT/scripts/remote/"*.sh 2>/dev/null \
        | grep -vE 'systemctl|chpasswd|install-(runtime-seam|bash|version|gateway)|permit-root-login|/etc/' \
        || true)"
    [ -z "$hits" ] || { echo "Unjustified root@-in-default sites:"; echo "$hits"; return 1; }
}
