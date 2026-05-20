#!/bin/bash
# Session monitor systemd service: install and uninstall
# L2: xrdp session health only (no OpenClAW gateway checks)

set -euo pipefail

install_service() {
    log_info "Installing session monitor service..."

    mkdir -p /var/lib/xrdp

    cat > /etc/systemd/system/openclaw-session-monitor.service << 'SERVICE_EOF'
[Unit]
Description=OpenClAW Session Monitor (L2 xrdp health)
After=xrdp.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/session-monitor.sh --daemon
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

    systemctl daemon-reload
    systemctl enable openclaw-session-monitor.service
    systemctl start openclaw-session-monitor.service

    log_info "Session monitor service installed and started"
}

uninstall_service() {
    log_info "Removing session monitor service..."

    systemctl stop openclaw-session-monitor.service 2>/dev/null || true
    systemctl disable openclaw-session-monitor.service 2>/dev/null || true
    rm -f /etc/systemd/system/openclaw-session-monitor.service
    rm -f /var/lib/xrdp/session-monitor-config.sh
    systemctl daemon-reload

    # Also clean up old name if present
    systemctl stop xrdp-session-monitor.service 2>/dev/null || true
    systemctl disable xrdp-session-monitor.service 2>/dev/null || true
    rm -f /etc/systemd/system/xrdp-session-monitor.service
    rm -f /usr/local/bin/xrdp-session-monitor
    systemctl daemon-reload

    log_info "Session monitor service removed"
}

export -f install_service uninstall_service
