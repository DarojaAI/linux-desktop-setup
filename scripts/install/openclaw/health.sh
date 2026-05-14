#!/bin/bash
# OpenClaw Health Probe - Self-healing foundation
# Exit codes: 0=healthy, 1=process dead, 2=endpoint fail, 3=Discord issue

set -euo pipefail

TARGET_USER="${TARGET_USER:-desktopuser}"
OPENCLAW_PORT="${OPENCLAW_PORT:-18789}"
MAX_RETRIES=3  # Reserved for retry logic in Task 2 (self-healing)

# Source lib for logging
_lib_sh_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd -P)/scripts/deploy"
source "${_lib_sh_dir}/lib.sh" 2>/dev/null || {
    # Fallback logging if lib.sh not available
    log_info() { echo "[INFO] $1"; }
    log_warn() { echo "[WARN] $1"; }
    log_error() { echo "[ERROR] $1"; }
}

check_process() {
    if pgrep -f "openclaw gateway.*$OPENCLAW_PORT" > /dev/null; then
        log_info "Process check: PASS (gateway running on port $OPENCLAW_PORT)"
        return 0
    else
        log_error "Process check: FAIL (gateway not running on port $OPENCLAW_PORT)"
        return 1
    fi
}

check_endpoint() {
    local url="http://localhost:$OPENCLAW_PORT/health"
    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null) || response="000"

    if [[ "$response" == "200" ]]; then
        log_info "Endpoint check: PASS (health endpoint returned 200)"
        return 0
    else
        log_error "Endpoint check: FAIL (health endpoint returned $response)"
        return 2
    fi
}

check_discord() {
    local config_file="/home/$TARGET_USER/.openclaw/openclaw.json"

    if [[ ! -f "$config_file" ]]; then
        log_warn "Discord check: SKIP (config not found)"
        return 0
    fi

    # Check environment variable first (standard approach), fall back to file extraction
    local bot_token="${DISCORD_BOT_TOKEN:-}"

    if [[ -z "$bot_token" ]]; then
        bot_token=$(sudo -u "$TARGET_USER" grep -h "DISCORD_BOT_TOKEN" /home/$TARGET_USER/.config/systemd/user/openclaw-gateway.service.d/override.conf 2>/dev/null | cut -d= -f2- | tr -d '"' | head -1)
    fi

    if [[ -z "$bot_token" ]]; then
        log_warn "Discord check: SKIP (no bot token found)"
        return 0
    fi

    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bot $bot_token" \
        "https://discord.com/api/v10/users/@me" --max-time 5 2>/dev/null) || response="000"

    if [[ "$response" == "200" ]]; then
        log_info "Discord check: PASS (bot API reachable)"
        return 0
    else
        log_error "Discord check: FAIL (bot API returned $response)"
        return 3
    fi
}

check_gateway_log() {
    # Scan gateway log for critical Discord disconnection events
    # These indicate the gateway is alive but cut off from Discord
    local log_file="${OPENCLAW_LOG_FILE:-/var/log/openclaw-gateway.log}"
    local cutoff_time
    cutoff_time=$(date -d '5 minutes ago' +%s 2>/dev/null || date -u -v-5M +%s 2>/dev/null)

    if [[ ! -f "$log_file" ]]; then
        return 0  # No log file = can't check, skip
    fi

    # Find lines with websocket close within last 5 minutes
    local recent_closes
    recent_closes=$(grep -c "Gateway websocket closed: 1006" "$log_file" 2>/dev/null || true)

    if [[ -n "$recent_closes" && "$recent_closes" -gt 0 ]]; then
        log_warn "Discord WebSocket 1006 disconnect detected in log ($recent_closes occurrences)"
        return 3  # Discord issue — trigger restart
    fi

    return 0
}

restart_with_backoff() {
    local attempt=1
    local delay=5
    local max_attempts=${MAX_RETRIES:-3}

    # All VMs are established with systemd; check the unit file directly.
    if [[ ! -f "/home/$TARGET_USER/.config/systemd/user/openclaw-gateway.service" ]]; then
        log_warn "systemd unit file not found"
        return 1
    fi

    log_info "Restarting via systemd..."
    sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$TARGET_USER")" \
        openclaw gateway stop 2>/dev/null || true
    sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$TARGET_USER")" \
        systemctl --user stop openclaw-gateway.service 2>/dev/null || true
    pkill -x openclaw 2>/dev/null || true
    fuser -k "$OPENCLAW_PORT"/tcp 2>/dev/null || true
    rm -f "/run/user/$(id -u "$TARGET_USER")/openclaw-gateway.pid" 2>/dev/null || true
    sleep 2

    while [[ $attempt -le $max_attempts ]]; do
        log_info "Restart attempt $attempt/$max_attempts"

        # Reset any previous start-limit-hit state
        sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$TARGET_USER")" \
            systemctl --user reset-failed openclaw-gateway.service 2>/dev/null || true

        sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$TARGET_USER")" \
            systemctl --user restart openclaw-gateway.service

        sleep 2

        # Verify by port binding (is-active fails over non-interactive SSH)
        for _ in {1..10}; do
            if ss -tlnp | grep -q ":$OPENCLAW_PORT "; then
                log_info "Restart successful (systemd)"
                return 0
            fi
            sleep 1
        done

        log_warn "Port $OPENCLAW_PORT not bound after restart, retrying..."
        attempt=$((attempt + 1))
        delay=$((delay * 3))
        sleep "$delay"
    done

    log_error "Restart failed after $max_attempts attempts"
    return 1
}

main() {
    local exit_code=0

    log_info "=== OpenClaw Health Check ==="

    # Check endpoint first — verifies the gateway is actually responsive
    # (process may be alive but gateway crashed, causing zombie state)
    if ! check_endpoint; then
        log_warn "Endpoint check failed — gateway not responding"
        exit_code=2
    fi

    # Check log for WebSocket 1006 disconnects (Discord cut off, process alive)
    local log_result=0
    check_gateway_log || log_result=$?
    if [[ $log_result -ne 0 ]]; then
        log_warn "Gateway log indicates Discord disconnection"
        exit_code=3
    fi

    # Check Discord API auth — a 401 means the token is invalid and restarting
    # will NEVER fix it. We must escalate, not spiral.
    local discord_status
    discord_status=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bot ${DISCORD_BOT_TOKEN:-}" \
        "https://discord.com/api/v10/users/@me" --max-time 5 2>/dev/null) || discord_status="000"
    if [[ "$discord_status" == "401" ]]; then
        log_error "Discord bot token INVALID (401) — restart will not help. Update DISCORD_BOT_TOKEN in GitHub secrets."
        exit_code=4
    elif [[ "$discord_status" != "200" ]]; then
        log_warn "Discord API returned $discord_status (transient, may recover on restart)"
        [[ $exit_code -eq 0 ]] && exit_code=3
    fi

    # Check process only if endpoint and log checks passed
    if [[ $exit_code -eq 0 ]] && ! check_process; then
        exit_code=1
    fi

    # If any check failed, attempt restart — EXCEPT auth failures (exit 4)
    if [[ $exit_code -eq 4 ]]; then
        log_error "Health check CRITICAL: manual intervention required (invalid Discord token)"
    elif [[ $exit_code -ne 0 ]]; then
        log_warn "Health checks failed (exit code $exit_code) — attempting self-heal..."
        if restart_with_backoff; then
            log_info "Self-heal: restart succeeded"
            exit_code=0
        else
            log_error "Self-heal: restart FAILED"
        fi
    else
        log_info "Overall: HEALTHY"
    fi

    return $exit_code

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
