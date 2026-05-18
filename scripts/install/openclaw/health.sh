#!/bin/bash
# OpenClaw Health Probe — Self-healing foundation
# Exit codes:
#   0 = healthy
#   1 = process dead
#   2 = endpoint fail
#   3 = Discord transient issue (restart may help)
#   4 = Discord auth failure (manual fix required — never restart)
#   5 = OpenRouter auth failure (manual fix required — never restart)
set -euo pipefail

TARGET_USER="${TARGET_USER:-desktopuser}"
OPENCLAW_PORT="${OPENCLAW_PORT:-18789}"
MAX_RETRIES=3

# Circuit breaker: prevent restart loops that burn Discord tokens
CIRCUIT_BREAKER_FILE="/tmp/openclaw-health-restarts.state"
CIRCUIT_BREAKER_MAX=3
CIRCUIT_BREAKER_WINDOW=600  # 10 minutes in seconds

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

# ── openrouter api validation ──
# A missing or invalid OpenRouter API key prevents ALL AI responses.
# Restarting will NEVER fix this. Must update OPENROUTER_API_KEY.
check_openrouter() {
	local config_file="/home/$TARGET_USER/.openclaw/openclaw.json"
	local api_key=""

	# Extract key from systemd override (same as discord token logic)
	if [[ -f "/home/$TARGET_USER/.config/systemd/user/openclaw-gateway.service.d/override.conf" ]]; then
		api_key=$(grep "^Environment=OPENROUTER_API_KEY=" "/home/$TARGET_USER/.config/systemd/user/openclaw-gateway.service.d/override.conf" 2>/dev/null | cut -d= -f3- | tr -d '"' | head -1)
	fi
	if [[ -z "$api_key" ]]; then
		api_key="${OPENROUTER_API_KEY:-}"
	fi

	if [[ -z "$api_key" ]]; then
		log_error "OpenRouter check: FAIL — API key MISSING from systemd override and env"
		log_error "  Fix: ensure OPENROUTER_API_KEY is in GitHub secrets and deploy inputs"
		return 5
	fi

	local http_code
	http_code=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $api_key" \
		"https://openrouter.ai/api/v1/models" --max-time 10 2>/dev/null) || http_code="000"

	if [[ "$http_code" == "401" ]]; then
		log_error "OpenRouter check: FAIL — API key INVALID (401)"
		log_error "  Restart will NOT fix this. Update OPENROUTER_API_KEY in GitHub secrets."
		return 5
	elif [[ "$http_code" != "200" ]]; then
		log_error "OpenRouter check: FAIL — API returned HTTP $http_code"
		return 3
	fi

	# Check configured default model exists in catalog
	if [[ -f "$config_file" ]]; then
		local default_model
		default_model=$(jq -r '.agents.defaults.model // empty' "$config_file" 2>/dev/null || true)
		if [[ -n "$default_model" ]]; then
			local lookup_model="$default_model"
			if [[ "$lookup_model" == openrouter/* ]]; then
				lookup_model="${lookup_model#openrouter/}"
			fi
			if ! curl -s -H "Authorization: Bearer $api_key" "https://openrouter.ai/api/v1/models" --max-time 15 2>/dev/null | \
				jq -e --arg m "$lookup_model" '.data[]? | select(.id == $m)' > /dev/null 2>&1; then
				log_warn "OpenRouter check: model '$default_model' not found in catalog"
				return 3
			fi
		fi
	fi

	log_info "OpenRouter check: PASS (key valid, model present)"
	return 0
}

# ── gateway log scan (RECENT only) ──
# Only looks at the last 5 minutes of log entries to avoid false positives
# from historical disconnects.
check_gateway_log() {
	local log_file
	log_file=$(get_openclaw_log_file) || return 0

	local recent_closes
	recent_closes=$(grep -E "$(date -d '5 minutes ago' '+%Y-%m-%dT%H:'|sed 's/.$//')|$(date -d '5 minutes ago' '+%Y-%m-%d %H:'|sed 's/.$//')" "$log_file" 2>/dev/null | \
		grep -c "Gateway websocket closed: 1006" || true)

	if [[ -n "$recent_closes" && "$recent_closes" -gt 0 ]]; then
		log_warn "Discord WebSocket 1006 disconnect detected in last 5 minutes ($recent_closes occurrences)"
		return 3
	fi

	local recent_auth_fail
	recent_auth_fail=$(grep -E "$(date -d '5 minutes ago' '+%Y-%m-%dT%H:'|sed 's/.$//')|$(date -d '5 minutes ago' '+%Y-%m-%d %H:'|sed 's/.$//')" "$log_file" 2>/dev/null | \
		grep -ci "authentication failed\|invalid token\|401\|unauthorized" || true)
	if [[ -n "$recent_auth_fail" && "$recent_auth_fail" -gt 0 ]]; then
		log_error "Discord auth failures in last 5 minutes ($recent_auth_fail occurrences)"
		return 4
	fi

	# Detect Discord gateway rate-limit backoff (restart will NOT help)
	local recent_exits
	recent_exits=$(grep -E "$(date -d '5 minutes ago' '+%Y-%m-%dT%H:'|sed 's/.$//')|$(date -d '5 minutes ago' '+%Y-%m-%d %H:'|sed 's/.$//')" "$log_file" 2>/dev/null | \
		grep -c "channel exited: Failed to get gateway information" || true)
	if [[ -n "$recent_exits" && "$recent_exits" -gt 2 ]]; then
		log_warn "Discord gateway rate-limit detected ($recent_exits channel exits) � restart will NOT help"
		return 3
	fi

	return 0
}


# ── Find the active OpenClaw log file ──
get_openclaw_log_file() {
	local log_dir="/tmp/openclaw"
	local legacy_log="${OPENCLAW_LOG_FILE:-/var/log/openclaw-gateway.log}"

	if [[ -d "$log_dir" ]]; then
		local latest_log
		latest_log=$(ls -t "$log_dir"/openclaw-*.log 2>/dev/null | head -1)
		if [[ -n "$latest_log" ]]; then
			echo "$latest_log"
			return 0
		fi
	fi

	if [[ -f "$legacy_log" ]]; then
		echo "$legacy_log"
		return 0
	fi

	return 1
}

# ── Circuit breaker: stop restart loops that burn Discord tokens ──
# After cooldown (15 min), permits ONE recovery restart so the gateway isn't
# permanently stuck dead after a transient Discord rate-limit expires.
check_circuit_breaker() {
	local now
	now=$(date +%s)
	local restarts=()
	local last_restart=0

	if [[ -f "$CIRCUIT_BREAKER_FILE" ]]; then
		while IFS= read -r line; do
			[[ -n "$line" ]] && restarts+=("$line")
		done < "$CIRCUIT_BREAKER_FILE"
	fi

	# Prune entries outside the window, track most recent
	local valid=()
	for ts in "${restarts[@]}"; do
		if [[ $((now - ts)) -lt $CIRCUIT_BREAKER_WINDOW ]]; then
			valid+=("$ts")
		fi
		if [[ "$ts" -gt "$last_restart" ]]; then
			last_restart="$ts"
		fi
	done

	if [[ ${#valid[@]} -gt 0 ]]; then
		printf "%s\n" "${valid[@]}" > "$CIRCUIT_BREAKER_FILE"
	else
		: > "$CIRCUIT_BREAKER_FILE"
	fi

	local cooldown=900  # 15 minutes
	if [[ ${#valid[@]} -ge $CIRCUIT_BREAKER_MAX ]]; then
		if [[ $((now - last_restart)) -gt $cooldown ]]; then
			log_warn "CIRCUIT BREAKER: cooldown elapsed ($(( (now - last_restart) / 60 ))m) — allowing ONE recovery restart"
			# Drop oldest entry so we can restart once
			local new_valid=("${valid[@]:1}")
			if [[ ${#new_valid[@]} -gt 0 ]]; then
				printf "%s\n" "${new_valid[@]}" > "$CIRCUIT_BREAKER_FILE"
			else
				: > "$CIRCUIT_BREAKER_FILE"
			fi
			return 0
		fi
		log_error "CIRCUIT BREAKER: ${#valid[@]} restarts in ${CIRCUIT_BREAKER_WINDOW}s — auto-restart DISABLED"
		return 1
	fi

	return 0
}

record_restart() {
	date +%s >> "$CIRCUIT_BREAKER_FILE"
}

# ── Check if Discord WebSocket actually connected ──
check_discord_websocket_ready() {
	local log_file
	log_file=$(get_openclaw_log_file) || return 0

	local last_config_line
	last_config_line=$(grep -n "loading configuration" "$log_file" 2>/dev/null | tail -1 | cut -d: -f1)
	if [[ -z "$last_config_line" ]]; then
		return 0
	fi

	local total_lines tail_lines startup_tail
	total_lines=$(wc -l < "$log_file")
	tail_lines=$((total_lines - last_config_line + 1))
	startup_tail=$(tail -n "$tail_lines" "$log_file" 2>/dev/null)

	if echo "$startup_tail" | grep -q "awaiting gateway readiness"; then
		if ! echo "$startup_tail" | grep -q "gateway ready"; then
			log_error "Discord WebSocket STUCK: 'awaiting gateway readiness' but NO 'gateway ready'"
			return 3
		fi
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

	# OpenRouter auth check — also CRITICAL and never recoverable by restart
	local or_code=0
	check_openrouter || or_code=$?
	if [[ $or_code -eq 5 ]]; then
		exit_code=5
	elif [[ $or_code -ne 0 ]]; then
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

	# If auth failure (exit 4 or 5): escalate, NEVER restart
	if [[ $exit_code -eq 4 || $exit_code -eq 5 ]]; then
		log_error "=== Health check CRITICAL ==="
		if [[ $exit_code -eq 4 ]]; then
			log_error "Discord authentication failed. This CANNOT be fixed by restart."
			log_error "Action required: update DISCORD_BOT_TOKEN in GitHub secrets."
		else
			log_error "OpenRouter authentication failed. This CANNOT be fixed by restart."
			log_error "Action required: update OPENROUTER_API_KEY in GitHub secrets."
		fi
	# Check Discord WebSocket actually connected (REST 200 ≠ gateway ready)
	local ws_result=0
	if [[ $exit_code -eq 0 ]]; then
		check_discord_websocket_ready || ws_result=1
		if [[ $ws_result -ne 0 ]]; then
			log_warn "Gateway log indicates Discord WebSocket STUCK"
			exit_code=3
		fi
	fi

	# For other failures: attempt restart (unless circuit breaker is open)
	elif [[ $exit_code -ne 0 ]]; then
		if ! check_circuit_breaker; then
			log_error "Self-heal BLOCKED by circuit breaker — gateway will NOT be restarted"
			return 1
		fi
		log_warn "Health checks failed (exit code $exit_code) — attempting self-heal..."
		record_restart
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
