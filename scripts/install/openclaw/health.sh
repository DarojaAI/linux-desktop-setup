#!/bin/bash
# OpenClaw Health Probe — Self-healing foundation
# Exit codes:
#   0 = healthy
#   1 = process dead
#   2 = endpoint fail
#   3 = Discord transient issue (restart may help)
#   4 = Discord auth failure (manual fix required — never restart)
set -euo pipefail

TARGET_USER="${TARGET_USER:-desktopuser}"
OPENCLAW_PORT="${OPENCLAW_PORT:-18789}"
MAX_RETRIES=3

# Source lib for logging
_lib_sh_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd -P)/scripts/deploy"
source "${_lib_sh_dir}/lib.sh" 2>/dev/null || {
	log_info() { echo "[INFO] $1"; }
	log_warn() { echo "[WARN] $1"; }
	log_error() { echo "[ERROR] $1"; }
}

# ── endpoint check ──
# Must return 200. A non-200 or unreachable gateway is NOT healthy.
check_endpoint() {
	local url="http://localhost:$OPENCLAW_PORT/health"
	local response
	response=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null) || response="000"

	if [[ "$response" == "200" ]]; then
		log_info "Endpoint check: PASS (200 OK)"
		return 0
	else
		log_error "Endpoint check: FAIL (HTTP $response)"
		return 2
	fi
}

# ── process check ──
# Use -x (exact match) — Node process.title is "openclaw", not "openclaw gateway"
# We ALWAYS run this, not conditional on endpoint state.
check_process() {
	if pgrep -x openclaw > /dev/null; then
		log_info "Process check: PASS (openclaw running)"
		return 0
	else
		log_error "Process check: FAIL (openclaw not running)"
		return 1
	fi
}

# ── discord api auth check ──
# A missing token or invalid token (401) is a HARD failure.
# Restarting a bad token will NEVER fix it and will burn the token faster.
check_discord() {
	local config_file="/home/$TARGET_USER/.openclaw/openclaw.json"

	# Extract token from systemd override (the actual runtime source)
	local bot_token=""
	if [[ -f "/home/$TARGET_USER/.config/systemd/user/openclaw-gateway.service.d/override.conf" ]]; then
		bot_token=$(grep "^Environment=DISCORD_BOT_TOKEN=" "/home/$TARGET_USER/.config/systemd/user/openclaw-gateway.service.d/override.conf" 2>/dev/null | cut -d= -f3- | tr -d '"' | head -1)
	fi

	# Also try env var as fallback (for manual runs)
	if [[ -z "$bot_token" ]]; then
		bot_token="${DISCORD_BOT_TOKEN:-}"
	fi

	if [[ -z "$bot_token" ]]; then
		log_error "Discord check: FAIL — bot token MISSING from systemd override and env"
		log_error "  Fix: ensure DISCORD_BOT_TOKEN is in GitHub secrets and deploy inputs"
		return 4
	fi

	local response
	response=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bot $bot_token" \
		"https://discord.com/api/v10/users/@me" --max-time 5 2>/dev/null) || response="000"

	if [[ "$response" == "200" ]]; then
		log_info "Discord check: PASS (token valid)"
		return 0
	elif [[ "$response" == "401" ]]; then
		log_error "Discord check: FAIL — token INVALID (401)"
		log_error "  Restart will NOT fix this. Update DISCORD_BOT_TOKEN in GitHub secrets."
		return 4
	else
		log_error "Discord check: FAIL — Discord API returned $response"
		return 3
	fi
}

# ── gateway log scan (RECENT only) ──
# Only looks at the last 5 minutes of log entries to avoid false positives
# from historical disconnects.
check_gateway_log() {
	local log_file="${OPENCLAW_LOG_FILE:-/var/log/openclaw-gateway.log}"

	if [[ ! -f "$log_file" ]]; then
		log_warn "Gateway log not found at $log_file — skipping log scan"
		# If the log file is missing but Discord is configured, we should still
		# check Discord API directly (already done in check_discord)
		return 0
	fi

	# Find lines WITHIN the last 5 minutes (using journalctl timestamp format or ISO)
	local recent_closes
	recent_closes=$(grep -E "$(date -d '5 minutes ago' '+%Y-%m-%dT%H:'|sed 's/.$//')|$(date -d '5 minutes ago' '+%Y-%m-%d %H:'|sed 's/.$//')" "$log_file" 2>/dev/null | \
		grep -c "Gateway websocket closed: 1006" || true)

	if [[ -n "$recent_closes" && "$recent_closes" -gt 0 ]]; then
		log_warn "Discord WebSocket 1006 disconnect detected in last 5 minutes ($recent_closes occurrences)"
		return 3
	fi

	# Also check for recent auth failures in the log
	local recent_auth_fail
	recent_auth_fail=$(grep -E "$(date -d '5 minutes ago' '+%Y-%m-%dT%H:'|sed 's/.$//')|$(date -d '5 minutes ago' '+%Y-%m-%d %H:'|sed 's/.$//')" "$log_file" 2>/dev/null | \
		grep -ci "authentication failed\|invalid token\|401\|unauthorized" || true)
	if [[ -n "$recent_auth_fail" && "$recent_auth_fail" -gt 0 ]]; then
		log_error "Discord auth failures in last 5 minutes ($recent_auth_fail occurrences)"
		return 4
	fi

	return 0
}

# ── restart with backoff (does NOT restart on auth failures) ──
restart_with_backoff() {
	local attempt=1
	local delay=5
	local max_attempts=${MAX_RETRIES:-3}

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

		sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$TARGET_USER")" \
			systemctl --user reset-failed openclaw-gateway.service 2>/dev/null || true
		sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$TARGET_USER")" \
			systemctl --user restart openclaw-gateway.service

		sleep 2

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

	# Check endpoint first — a crashed gateway still returns a non-200
	if ! check_endpoint; then
		exit_code=2
	fi

	# Process check is independent — we always want to know if the process is alive
	if ! check_process; then
		exit_code=1
	fi

	# Discord auth check — this is CRITICAL and never recoverable by restart
	local discord_code=0
	check_discord || discord_code=$?
	if [[ $discord_code -eq 4 ]]; then
		exit_code=4
	elif [[ $discord_code -ne 0 ]]; then
		# Transient Discord issue
		[[ $exit_code -eq 0 ]] && exit_code=3
	fi

	# Gateway log scan (recent only) for WebSocket disconnects/auth failures
	local log_code=0
	check_gateway_log || log_code=$?
	if [[ $log_code -eq 4 ]]; then
		exit_code=4
	elif [[ $log_code -ne 0 ]]; then
		[[ $exit_code -eq 0 ]] && exit_code=3
	fi

	# If auth failure (exit 4): escalate, NEVER restart
	if [[ $exit_code -eq 4 ]]; then
		log_error "=== Health check CRITICAL ==="
		log_error "Discord authentication failed. This CANNOT be fixed by restart."
		log_error "Action required: update DISCORD_BOT_TOKEN in GitHub secrets."
	# For other failures: attempt restart (restart-loop already blocked by rate limits)
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
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
