# Session Monitoring Reference

The monitoring system watches your RDP desktop sessions continuously, alerting you to crashes and resource problems within 30 seconds rather than leaving you to discover them hours later.

For the full guide including crash analysis and alert response, see [Crash Recovery Guide](CRASH-RECOVERY.md).

---

## Quick Health Check

```bash
bash scripts/analyze-session-logs.sh --summary
```

---

## The Four Analysis Commands

```bash
# Overall health summary
bash scripts/analyze-session-logs.sh --summary

# Find crashes and errors
bash scripts/analyze-session-logs.sh --crashes

# Memory usage analysis
bash scripts/analyze-session-logs.sh --memory

# Session timeline (connect/disconnect history)
bash scripts/analyze-session-logs.sh --timeline
```

---

## GitHub Issues Integration

The monitor can automatically create GitHub issues when critical errors occur, so you get notified and I can analyze problems.

### Enable GitHub Issues

1. Set environment variables in the systemd service:
```bash
sudo systemctl edit xrdp-session-monitor.service
```

Add under `[Service]`:
```ini
Environment="GITHUB_REPO=username/repo"
Environment="GITHUB_TOKEN=ghp_xxxx"
Environment="AUTO_ISSUE_ENABLED=true"
```

2. Restart the service:
```bash
sudo systemctl restart xrdp-session-monitor.service
```

### What Creates Issues

| Event | Severity | Labels |
|-------|----------|--------|
| Session crash (segfault) | critical | desktop, auto-detected, critical |
| Memory critical (>80%) | critical | desktop, auto-detected, critical |
| CPU critical (>75%) | critical | desktop, auto-detected, critical |

### Using Issues

- Issues appear in your GitHub repo automatically
- Each issue includes: error details, system state, log file paths, suggested fixes
- Review open issues to spot patterns over time

---

## Real-Time Monitoring

```bash
# Watch all monitoring activity
tail -f /var/log/xrdp/session-monitor.log

# Watch alerts only
tail -f /var/log/xrdp/session-alerts.log

# Watch service output
journalctl -u xrdp-session-monitor.service -f
```

---

## How It Works

### Session Startup (`startwm.sh`)
- Sets a 2 GB per-process virtual memory limit (prevents GNOME from consuming unlimited RAM)
- Logs session start time, available memory, and CPU count
- Registers a crash handler — if the session exits unexpectedly, it logs the exit code, signal, and memory snapshot before closing

### Continuous Monitoring (`xrdp-session-monitor` service)
- Runs every 30 seconds, automatically, in the background
- Checks memory usage (alerts at 80% of system RAM)
- Checks CPU usage (alerts at 75%)
- Scans xrdp logs for crash indicators
- Writes results to log files and syslog

### Analysis Tools (`analyze-session-logs.sh`)
- Reads monitoring logs and formats them for human review
- Extracts crash details, memory trends, and session timelines

---

## Service Management

```bash
# Check status
systemctl status xrdp-session-monitor.service

# View service logs
journalctl -u xrdp-session-monitor.service -n 50

# Restart service
sudo systemctl restart xrdp-session-monitor.service

# Disable monitoring
sudo systemctl stop xrdp-session-monitor.service
sudo systemctl disable xrdp-session-monitor.service

# Re-enable monitoring
sudo systemctl enable xrdp-session-monitor.service
sudo systemctl start xrdp-session-monitor.service
```

---

## Thresholds

Default settings:
- **Memory alert:** 80% of available system RAM
- **CPU alert:** 75% utilization
- **Per-process memory limit:** 2 GB virtual memory

To adjust thresholds:
```bash
# Edit the config file
nano /var/lib/xrdp/session-monitor-config.sh

# Then restart the service
sudo systemctl restart xrdp-session-monitor.service
```

---

## Log Files

| File | Contents |
|------|----------|
| `/var/log/xrdp/session-monitor.log` | All health checks (every 30 seconds) |
| `/var/log/xrdp/session-alerts.log` | Alerts only |
| `/var/log/xrdp-sesman.log` | xrdp session manager log |

---

## Troubleshooting the Monitor

### Service not running
```bash
systemctl status xrdp-session-monitor.service
journalctl -u xrdp-session-monitor.service -n 50
sudo systemctl restart xrdp-session-monitor.service
```

### No data in logs
```bash
# Check log directory exists and is writable
ls -la /var/log/xrdp/

# Check the service is enabled (starts on boot)
systemctl is-enabled xrdp-session-monitor.service
```

### High memory alerts
```bash
# See what processes are using the most memory
ps aux --sort=-%mem | head -10

# View memory trends
bash scripts/analyze-session-logs.sh --memory
```

---

## Session Cleanup

A background job runs every 5 minutes to clean up orphaned processes from old RDP sessions.

```bash
# View cleanup logs
tail -f /var/log/xrdp/session-cleanup.log

# Run cleanup manually (dry-run)
sudo bash /tmp/cleanup-sessions.sh --dry-run

# Run cleanup manually (for real)
sudo bash /tmp/cleanup-sessions.sh
```

### How it works
- Identifies the most recent Xvnc session (highest PID) as the active session
- Kills orphaned processes from old sessions: `xrdp-chansrv`, `gnome-shell`, `code`, `chrome`, `Xvnc`
- Preserves all processes in the active session
- Logs actions to `/var/log/xrdp/session-cleanup.log`

### Process patterns targeted
| Pattern | Description |
|---------|-------------|
| `xrdp-chansrv` | RDP channel service |
| `pw-cli.*xrdp` | xrdp process wrapper |
| `gnome-shell` | GNOME shell (orphaned) |
| `code` | VS Code instances |
| `chrome` | Chromium instances |
| `Xvnc` | Old VNC servers |