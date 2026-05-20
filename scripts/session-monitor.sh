#!/bin/bash
# Session Monitoring Daemon - entrypoint
# Usage: sudo bash scripts/session-monitor.sh [--enable|--disable|--test|--daemon]

set -euo pipefail

RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' NC='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

_monitor_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/monitor" && pwd -P)"
# shellcheck source=monitor/session-cleanup.sh
source "$_monitor_dir/session-cleanup.sh"
# shellcheck source=monitor/session-health.sh
source "$_monitor_dir/session-health.sh"
# shellcheck source=monitor/session-service.sh
source "$_monitor_dir/session-service.sh"

run_test() {
    log_info "Running session monitor test..."
    init_logs
    monitor_active_sessions
    monitor_crash_logs
    generate_report
    echo ""; echo "Monitor log (last 20 lines):"; tail -20 "$MONITOR_LOG"
    echo ""; echo "Alert log (last 20 lines):";  tail -20 "$ALERT_LOG"
}

run_daemon() {
    [ -f /var/lib/xrdp/session-monitor-config.sh ] && source /var/lib/xrdp/session-monitor-config.sh
    init_logs
    while true; do
        monitor_active_sessions
        monitor_crash_logs
        cleanup_orphaned_sessions
        generate_report
        sleep 30
    done
}

case "${1:-}" in
    --enable)  install_service ;;
    --disable) uninstall_service ;;
    --test)    run_test ;;
    --daemon)  run_daemon ;;
    "")        run_daemon ;;
    *)
        echo "Usage: sudo bash scripts/session-monitor.sh [--enable|--disable|--test|--daemon]"
        exit 1
        ;;
esac
