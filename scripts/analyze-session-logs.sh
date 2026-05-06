#!/bin/bash
# Session Log Analysis Tool
# Quickly analyze RDP session crashes and performance issues
# Usage: sudo bash scripts/analyze-session-logs.sh [--crashes|--memory|--timeline|--summary]

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_header() { echo -e "${BLUE}=== $1 ===${NC}"; }

# === Analysis Functions ===

analyze_crashes() {
    log_header "Session Crashes"

    local sesman_log="/var/log/xrdp-sesman.log"
    if [ ! -f "$sesman_log" ]; then
        log_error "xrdp-sesman.log not found at $sesman_log"
        return 1
    fi

    echo ""
    log_info "Looking for window manager crashes..."

    local crash_count=$(grep -ic "window manager.*exited\|crashed\|exit.*signal" "$sesman_log" || echo "0")

    if [ "$crash_count" -gt 0 ]; then
        grep -i "window manager.*exited\|crashed\|exit.*signal" "$sesman_log" | tail -20 | while read -r line; do
            echo "  $line"
        done
    else
        log_info "No crashes detected in recent logs"
    fi

    echo ""
    log_info "Recent error messages:"
    grep -i "error\|warn" "$sesman_log" | tail -10 | while read -r line; do
        echo "  $line"
    done
}

analyze_memory() {
    log_header "Memory Usage Analysis"

    local monitor_log="/var/log/xrdp/session-monitor.log"
    local alerts_log="/var/log/xrdp/session-alerts.log"

    if [ ! -f "$monitor_log" ]; then
        log_warn "session-monitor.log not found - enable monitoring with: sudo bash scripts/session-monitor.sh --enable"
        return 1
    fi

    echo ""
    log_info "Memory peaks from monitoring data:"
    grep -i "memory" "$monitor_log" 2>/dev/null | grep -oE "[0-9]+\.[0-9]+%" | sort -rn | uniq | head -5 | while read -r percent; do
        echo "  Peak: $percent of available memory"
    done

    echo ""
    log_info "Current active sessions:"
    ps aux | grep "[X]vnc" | awk '{printf "  Display %s: PID %d, Mem %.1f%% (%dMB), CPU %.1f%%\n", $11, $2, $4, $6/1024, $3}'

    if [ ! -f "$alerts_log" ]; then
        return 0
    fi

    echo ""
    log_info "Memory threshold alerts:"
    grep "HIGH_MEMORY" "$alerts_log" 2>/dev/null | tail -5 | while read -r line; do
        echo "  $line"
    done
}

analyze_timeline() {
    log_header "Session Timeline"

    local sesman_log="/var/log/xrdp-sesman.log"
    if [ ! -f "$sesman_log" ]; then
        log_error "xrdp-sesman.log not found at $sesman_log"
        return 1
    fi

    echo ""
    log_info "Session creation timeline:"
    grep -i "created session\|starting.*session" "$sesman_log" | tail -20 | while read -r line; do
        timestamp=$(echo "$line" | grep -oE "[0-9]{4}-[0-9]{2}-[0-9]{2}" || echo "")
        time=$(echo "$line" | grep -oE "[0-9]{2}:[0-9]{2}:[0-9]{2}" || echo "")
        display=$(echo "$line" | grep -oE "display :[0-9]+" || echo "")
        echo "  $timestamp $time - $display"
    done

    echo ""
    log_info "Session termination timeline:"
    grep -i "terminated session\|exited\|process.*exited" "$sesman_log" | tail -10 | while read -r line; do
        timestamp=$(echo "$line" | grep -oE "[0-9]{4}-[0-9]{2}-[0-9]{2}" || echo "")
        time=$(echo "$line" | grep -oE "[0-9]{2}:[0-9]{2}:[0-9]{2}" || echo "")
        reason=$(echo "$line" | grep -oE "username.*|signal.*|exit.*" | head -1 || echo "unknown")
        echo "  $timestamp $time - $reason"
    done
}

analyze_summary() {
    log_header "System Health Summary"

    echo ""
    log_info "RDP Service Status:"
    systemctl is-active xrdp && echo "  ✓ xrdp: running" || echo "  ✗ xrdp: not running"
    systemctl is-active xrdp-sesman && echo "  ✓ xrdp-sesman: running" || echo "  ✗ xrdp-sesman: not running"

    echo ""
    log_info "Session Monitor Status:"
    if systemctl is-active xrdp-session-monitor.service &>/dev/null; then
        echo "  ✓ Session monitor: running"
        local checks=$(grep -c "Session Monitor Check" /var/log/xrdp/session-monitor.log 2>/dev/null || echo "0")
        echo "    Checks performed: $checks"
    else
        echo "  ✗ Session monitor: not running"
    fi

    echo ""
    log_info "Current System Resources:"
    echo "  Memory: $(free -h | awk 'NR==2 {print $3 " / " $2}')"
    echo "  Disk: $(df / | awk 'NR==2 {print $3 " / " $2}')"
    echo "  Load: $(uptime | grep -oE "load average:.*" | cut -d: -f2)"

    echo ""
    log_info "Active RDP Sessions:"
    local session_count=$(ps aux | grep -c "[X]vnc" || echo "0")
    session_count=$((session_count - 1))  # Subtract grep process itself
    if [ "$session_count" -gt 0 ]; then
        echo "  Found $session_count active session(s)"
        ps aux | grep "[X]vnc" | awk '{printf "    - Display %s: %.1f%% memory, %.1f%% CPU\n", $11, $4, $3}'
    else
        echo "  No active sessions"
    fi

    echo ""
    log_info "Disk Space Alert Check:"
    local disk_usage=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
    if [ "$disk_usage" -gt 90 ]; then
        log_error "Disk usage critical: $disk_usage%"
    elif [ "$disk_usage" -gt 75 ]; then
        log_warn "Disk usage high: $disk_usage%"
    else
        echo "  ✓ Disk usage: $disk_usage% (normal)"
    fi
}

# === Main ===

case "${1:-}" in
    --crashes)
        analyze_crashes
        ;;
    --memory)
        analyze_memory
        ;;
    --timeline)
        analyze_timeline
        ;;
    --summary)
        analyze_summary
        ;;
    *)
        echo "Session Log Analysis Tool"
        echo ""
        echo "Usage: sudo bash scripts/analyze-session-logs.sh [OPTION]"
        echo ""
        echo "Options:"
        echo "  --crashes    Analyze session crashes and errors"
        echo "  --memory     Analyze memory usage patterns and alerts"
        echo "  --timeline   Show session creation/termination timeline"
        echo "  --summary    Overall system health summary"
        echo ""
        echo "Without options, runs full analysis:"
        analyze_crashes 2>/dev/null || true
        analyze_memory 2>/dev/null || true
        analyze_timeline 2>/dev/null || true
        analyze_summary
        ;;
esac
