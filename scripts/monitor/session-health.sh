#!/bin/bash
# Session health monitoring: process checks, crash log scanning, GitHub issue creation
#
# L2 responsibility: xrdp session health only.
# OpenClAW gateway health is handled by L3 (openclaw-watchdog.timer + openclaw-health-probe.timer).

set -euo pipefail

MONITOR_LOG="${MONITOR_LOG:-/var/log/xrdp/session-monitor.log}"
ALERT_LOG="${ALERT_LOG:-/var/log/xrdp/session-alerts.log}"
MEMORY_THRESHOLD="${MEMORY_THRESHOLD:-80}"
CPU_THRESHOLD="${CPU_THRESHOLD:-75}"
GITHUB_REPO="${GITHUB_REPO:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
AUTO_ISSUE_ENABLED="${AUTO_ISSUE_ENABLED:-false}"
ISSUE_SEVERITY_THRESHOLD="${ISSUE_SEVERITY_THRESHOLD:-warning}"
ISSUE_DEDUP_WINDOW=3600
LAST_ISSUE_TIME=0

init_logs() {
    mkdir -p /var/log/xrdp
    touch "$MONITOR_LOG" "$ALERT_LOG"
    chmod 644 "$MONITOR_LOG" "$ALERT_LOG"
}

monitor_active_sessions() {
    local timestamp; timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    {
        echo "[$timestamp] === Session Monitor Check ==="
        local xvnc_pids; xvnc_pids=$(pgrep -f "Xvnc" || true)

        if [ -z "$xvnc_pids" ]; then
            echo "[$timestamp] No active Xvnc sessions"
            return 0
        fi

        while IFS= read -r pid; do
            check_process_health "$pid" "$timestamp"
        done <<< "$xvnc_pids"

    } >> "$MONITOR_LOG" 2>&1
}

check_process_health() {
    local pid=$1
    local timestamp=$2
    local mem_info; mem_info=$(ps -p "$pid" -o %mem=,rss= 2>/dev/null || echo "0 0")
    local mem_percent; mem_percent=$(echo "$mem_info" | awk '{print $1}')
    local mem_kb; mem_kb=$(echo "$mem_info" | awk '{print $2}')
    local mem_mb=$(( mem_kb / 1024 ))
    local cpu_percent; cpu_percent=$(ps -p "$pid" -o %cpu= 2>/dev/null || echo "0")
    local display; display=$(ps -p "$pid" -o args= 2>/dev/null | grep -oE ':[0-9]+' | head -1 || echo "unknown")

    {
        echo "  [$timestamp] Display $display (PID $pid)"
        echo "    Memory: ${mem_percent}% (${mem_mb}MB), CPU: ${cpu_percent}%"
    } >> "$MONITOR_LOG" 2>&1

    if (( $(echo "$mem_percent > $MEMORY_THRESHOLD" | bc -l) )); then
        alert "HIGH_MEMORY" "Session $display (PID $pid) using ${mem_percent}% memory (${mem_mb}MB)" "$timestamp"
    fi

    if (( $(echo "$cpu_percent > $CPU_THRESHOLD" | bc -l) )); then
        alert "HIGH_CPU" "Session $display (PID $pid) using ${cpu_percent}% CPU" "$timestamp"
    fi
}

alert() {
    local alert_type=$1 message=$2 timestamp=$3

    echo "[$timestamp] [$alert_type] $message" >> "$ALERT_LOG" 2>&1
    logger -t "xrdp-session-monitor" -p warning "$alert_type: $message"

    local severity="info"
    case "$alert_type" in
        HIGH_MEMORY|HIGH_CPU|SERVICE_DOWN) severity="critical" ;;
        CLEANUP_ORPHAN) severity="warning" ;;
    esac

    if [[ "$severity" == "critical" ]]; then
        local body="## Error Details
- **Type:** $alert_type  **Timestamp:** $timestamp
- **Message:** $message

## System State
- Memory: $(free -h | awk '/Mem/{print $3 " used / " $7 " available"}')
- CPU Load: $(uptime | awk -F'load average:' '{print $2}')
- Uptime: $(uptime -p)"
        create_github_issue "$severity" "$alert_type at $timestamp" "$body" "desktop,auto-detected,$severity"
    fi
}

create_github_issue() {
    local severity="$1" title="$2" body="$3" labels="$4"

    [[ "$AUTO_ISSUE_ENABLED" == "true" ]] || return 0
    [[ -n "$GITHUB_REPO" && -n "$GITHUB_TOKEN" ]] || return 0

    local severity_level=0 threshold_level=0
    case "$severity" in critical) severity_level=3 ;; warning) severity_level=2 ;; info) severity_level=1 ;; esac
    case "$ISSUE_SEVERITY_THRESHOLD" in critical) threshold_level=3 ;; warning) threshold_level=2 ;; info) threshold_level=1 ;; esac
    [[ "$severity_level" -ge "$threshold_level" ]] || return 0

    local current_time; current_time=$(date +%s)
    [[ $(( current_time - LAST_ISSUE_TIME )) -ge "$ISSUE_DEDUP_WINDOW" ]] || return 0
    LAST_ISSUE_TIME=$current_time

    local issue_url
    issue_url=$(gh issue create \
        --repo "$GITHUB_REPO" \
        --title "[$severity] $title" \
        --body "$body" \
        --label "$labels" 2>&1) || {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Failed to create GitHub issue: $issue_url" >> "$ALERT_LOG"
        return 1
    }
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] GitHub issue created: $issue_url" >> "$ALERT_LOG"
}

monitor_crash_logs() {
    local timestamp; timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    [ -f /var/log/xrdp/xrdp-sesman.log ] || return 0

    local recent_errors; recent_errors=$(grep -i "error\|crashed\|exit" /var/log/xrdp/xrdp-sesman.log | tail -5 || true)
    [ -n "$recent_errors" ] || return 0

    { echo "[$timestamp] === Recent xrdp-sesman Errors ==="; echo "$recent_errors"; } >> "$ALERT_LOG" 2>&1

    if echo "$recent_errors" | grep -qi "crashed\|segfault\|segmentation"; then
        local body="## Error Details
- **Type:** Session crash  **Timestamp:** $timestamp  **Process:** xrdp-sesman

## Recent Errors
\`\`\`
$recent_errors
\`\`\`

## System State
- Memory: $(free -h | awk '/Mem/{print $3 " used / " $7 " available"}')
- Uptime: $(uptime -p)"
        create_github_issue "critical" "Session crash at $timestamp" "$body" "desktop,auto-detected,critical"
    fi
}

generate_report() {
    local timestamp; timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    {
        echo ""
        echo "=== Session Monitor Report - $timestamp ==="
        echo "Active Xvnc Sessions:"
        local sessions; sessions=$(ps aux | grep "[X]vnc" || true)
        echo "$sessions" | awk '{print $2, $3"% CPU", $4"% MEM", $11}'
        echo ""
        echo "Memory Usage Summary:"; free -h
        echo ""
        echo "Disk Usage:"; df -h /
        echo ""
        echo "Recent Alerts:"; tail -10 "$ALERT_LOG" 2>/dev/null || echo "  (none)"
    } >> "$MONITOR_LOG" 2>&1
}

export -f init_logs monitor_active_sessions check_process_health alert create_github_issue monitor_crash_logs generate_report
