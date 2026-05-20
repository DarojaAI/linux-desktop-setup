#!/bin/bash
# OpenClAW Health Probe — Report only, no restart
# Exit codes: 0=healthy, 1=process dead, 2=endpoint fail, 3=Discord auth fail, 4=OpenRouter auth fail, 5=model format warn

set -euo pipefail

TARGET_USER="${TARGET_USER:-desktopuser}"
OPENCLAW_PORT="${OPENCLAW_PORT:-18789}"
CONFIG_FILE="/home/$TARGET_USER/.openclaw/openclaw.json"
LOG_FILE="${LOG_FILE:-/var/log/openclaw-health.log}"

# Logging
log_info()  { echo "[INFO] $1"; }
log_warn()  { echo "[WARN] $1"; }
log_error() { echo "[ERROR] $1"; }

log_to_file() {
    local level="$1" msg="$2"
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$ts [$level] $msg" >> "$LOG_FILE"
}

check_process() {
    if pgrep -x "openclaw" > /dev/null; then
        log_info "Process check: PASS"
        return 0
    else
        log_error "Process check: FAIL (gateway not running)"
        return 1
    fi
}

check_endpoint() {
    local url="http://localhost:$OPENCLAW_PORT/health"
    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null) || response="000"

    if [[ "$response" == "200" ]]; then
        log_info "Endpoint check: PASS"
        return 0
    else
        log_error "Endpoint check: FAIL (HTTP $response)"
        return 2
    fi
}

check_discord() {
    local bot_token
    bot_token=$(grep "^Environment=DISCORD_BOT_TOKEN=" "/home/$TARGET_USER/.config/systemd/user/openclaw-gateway.service.d/override.conf" 2>/dev/null | cut -d= -f3- | head -1) || bot_token=""

    if [[ -z "$bot_token" ]]; then
        log_warn "Discord check: SKIP (no bot token)"
        return 0
    fi

    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bot $bot_token" \
        "https://discord.com/api/v10/users/@me" --max-time 5 2>/dev/null) || response="000"

    if [[ "$response" == "200" ]]; then
        log_info "Discord check: PASS"
        return 0
    else
        log_error "Discord check: FAIL (HTTP $response)"
        return 3
    fi
}

check_openrouter() {
    local api_key
    api_key=$(grep "^Environment=OPENROUTER_API_KEY=" "/home/$TARGET_USER/.config/systemd/user/openclaw-gateway.service.d/override.conf" 2>/dev/null | cut -d= -f3- | head -1) || api_key=""

    if [[ -z "$api_key" ]]; then
        log_warn "OpenRouter check: SKIP (no API key)"
        return 0
    fi

    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $api_key" \
        "https://openrouter.ai/api/v1/auth/key" --max-time 10 2>/dev/null) || response="000"

    if [[ "$response" == "200" ]]; then
        log_info "OpenRouter check: PASS"
        return 0
    elif [[ "$response" == "401" ]]; then
        log_error "OpenRouter check: FAIL (401 invalid key)"
        return 4
    else
        log_warn "OpenRouter check: WARN (HTTP $response)"
        return 0
    fi
}

check_model_format() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_warn "Model format check: SKIP (config not found)"
        return 0
    fi

    local model
    model=$(jq -r '.agents.defaults.model // empty' "$CONFIG_FILE" 2>/dev/null) || model=""

    if [[ -z "$model" ]]; then
        log_warn "Model format check: SKIP (no model configured)"
        return 0
    fi

    # Valid: string like "openrouter/anthropic/claude-sonnet-4-5" or object {"primary": "..."}
    if [[ "$model" == *"primary"* ]]; then
        # Object format — validate primary key exists
        local primary
        primary=$(echo "$model" | jq -r '.primary // empty' 2>/dev/null) || primary=""
        if [[ -z "$primary" ]]; then
            log_warn "Model format check: WARN (object missing 'primary' key)"
            return 5
        fi
        log_info "Model format check: PASS (object with primary=$primary)"
        return 0
    fi

    log_info "Model format check: PASS (string=$model)"
    return 0
}

main() {
    local exit_code=0

    log_info "=== OpenClAW Health Check ==="

    if ! check_process; then
        exit_code=1
    elif ! check_endpoint; then
        exit_code=2
    fi

    if ! check_discord; then
        [[ "$exit_code" -eq 0 ]] && exit_code=3
    fi

    if ! check_openrouter; then
        [[ "$exit_code" -eq 0 ]] && exit_code=4
    fi

    check_model_format || {
        [[ "$exit_code" -eq 0 ]] && exit_code=5
    }

    log_to_file "$([[ $exit_code -eq 0 ]] && echo INFO || echo FAIL)" "exit_code=$exit_code"
    return "$exit_code"
}

main "$@"
