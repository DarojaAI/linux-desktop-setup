#!/bin/bash
# Session monitor systemd service: install and uninstall

set -euo pipefail

_monitor_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=session-cleanup.sh
source "$_monitor_dir/session-cleanup.sh"
# shellcheck source=session-health.sh
source "$_monitor_dir/session-health.sh"

install_service() {
    log_info "Installing session monitor service..."

    mkdir -p /var/lib/xrdp

    cat > /usr/local/bin/xrdp-session-monitor << 'SCRIPT_EOF'
#!/bin/bash
set -euo pipefail
source /var/lib/xrdp/session-monitor-config.sh
init_logs
cleanup_orphaned_sessions
while true; do
    monitor_active_sessions
    monitor_crash_logs
    cleanup_orphaned_sessions
    generate_report
    sleep 30
done
SCRIPT_EOF
    chmod +x /usr/local/bin/xrdp-session-monitor

    cat > /etc/systemd/system/xrdp-session-monitor.service << 'SERVICE_EOF'
[Unit]
Description=XRDP Session Monitor
After=xrdp.service
Requires=xrdp.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/xrdp-session-monitor
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE_EOF

    cat > /var/lib/xrdp/session-monitor-config.sh << 'CONFIG_EOF'
MONITOR_LOG="/var/log/xrdp/session-monitor.log"
ALERT_LOG="/var/log/xrdp/session-alerts.log"
MEMORY_THRESHOLD=80
CPU_THRESHOLD=75

log_info() { echo "[INFO] $1"; }
log_warn() { echo "[WARN] $1"; }
log_error() { echo "[ERROR] $1"; }
CONFIG_EOF

    # Append function definitions from modular sources
    declare -f cleanup_orphaned_sessions >> /var/lib/xrdp/session-monitor-config.sh
    declare -f init_logs >> /var/lib/xrdp/session-monitor-config.sh
    declare -f monitor_active_sessions >> /var/lib/xrdp/session-monitor-config.sh
    declare -f monitor_crash_logs >> /var/lib/xrdp/session-monitor-config.sh
    declare -f generate_report >> /var/lib/xrdp/session-monitor-config.sh

    systemctl daemon-reload
    systemctl enable xrdp-session-monitor.service
    systemctl start xrdp-session-monitor.service

    log_info "Session monitor service installed and started"
}

uninstall_service() {
    log_info "Removing session monitor service..."

    systemctl stop xrdp-session-monitor.service 2>/dev/null || true
    systemctl disable xrdp-session-monitor.service 2>/dev/null || true
    rm -f /etc/systemd/system/xrdp-session-monitor.service
    rm -f /usr/local/bin/xrdp-session-monitor
    rm -f /var/lib/xrdp/session-monitor-config.sh
    systemctl daemon-reload

    log_info "Session monitor service removed"
}

export -f install_service uninstall_service
