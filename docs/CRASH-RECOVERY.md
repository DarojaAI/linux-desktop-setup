# Crash Recovery & Session Monitoring

## What This Does

When you're using the remote desktop and something goes wrong — a crash, memory exhaustion, or an unresponsive session — this system:

1. **Detects the problem within 30 seconds** (compared to not knowing until you reconnect hours later)
2. **Captures a snapshot** of what was happening — memory usage, CPU load, running processes — at the moment of the crash
3. **Writes everything to log files** so you can diagnose what happened

---

## The Two Components

### Session Monitor Service

A background service (`xrdp-session-monitor.service`) runs continuously and checks every 30 seconds:

- **Memory usage** — alerts if system memory exceeds 80%
- **CPU usage** — alerts if CPU exceeds 75%
- **Session health** — scans logs for recent crash indicators

This service starts automatically at boot and runs regardless of whether you're connected.

### Session Startup Script

When you connect via RDP, `startwm.sh` runs to start your desktop session. It also:

- Sets a **2 GB per-process memory limit** to prevent one runaway process from crashing everything
- Registers a **crash handler** — if the session exits unexpectedly, it logs the exit code, signal, and a memory snapshot before exiting

---

## Checking System Health

### Quick health summary
```bash
bash scripts/analyze-session-logs.sh --summary
```

### See recent crashes
```bash
bash scripts/analyze-session-logs.sh --crashes
```

### Memory usage over time
```bash
bash scripts/analyze-session-logs.sh --memory
```

### Session history (connects and disconnects)
```bash
bash scripts/analyze-session-logs.sh --timeline
```

### Watch the monitor in real time
```bash
tail -f /var/log/xrdp/session-monitor.log   # all checks
tail -f /var/log/xrdp/session-alerts.log    # alerts only
```

---

## What Happens When a Crash Occurs

| Time after crash | What happens |
|-----------------|-------------|
| 0 seconds | Session exits; startup script logs exit code, signal, and memory snapshot |
| ~5 seconds | xrdp detects the window manager exited |
| ~30 seconds | Monitor service checks logs and writes an alert |
| ~60 seconds | You can run `--crashes` to see the full report |

After a crash you'll typically see a blank screen or connection drop on your RDP client. Reconnect via Remote Desktop — xrdp will start a fresh session.

---

## Responding to Alerts

### High memory alert

If you see memory alerts in the logs:

```bash
# See what's using the most memory
ps aux --sort=-%mem | head -10
```

Common causes:
- Too many open browser tabs in Chromium
- Long-running VS Code sessions with many extensions
- GNOME Shell memory leak (disconnect and reconnect to reset)

If memory is consistently near the limit, consider increasing your server's RAM or reducing the per-process limit in `/etc/xrdp/startwm.sh`.

### High CPU alert

```bash
# See what's using CPU
ps aux --sort=-%cpu | head -10
```

A brief CPU spike is normal. Sustained high CPU (minutes, not seconds) is worth investigating.

---

## Managing the Monitor Service

```bash
# Check if it's running
systemctl status xrdp-session-monitor.service

# View its logs
journalctl -u xrdp-session-monitor.service -n 50

# Restart it
sudo systemctl restart xrdp-session-monitor.service

# Disable it (if you need to)
sudo systemctl stop xrdp-session-monitor.service
sudo systemctl disable xrdp-session-monitor.service

# Re-enable it
sudo systemctl enable xrdp-session-monitor.service
sudo systemctl start xrdp-session-monitor.service
```

---

## Adjusting Thresholds

Edit `/var/lib/xrdp/session-monitor-config.sh`:

```bash
MEMORY_THRESHOLD=80      # alert when system memory reaches 80%
CPU_THRESHOLD=75         # alert when CPU reaches 75%
```

Restart the service after changing:
```bash
sudo systemctl restart xrdp-session-monitor.service
```

---

## Log File Locations

| File | Contents |
|------|----------|
| `/var/log/xrdp/session-monitor.log` | All health checks (every 30 seconds) |
| `/var/log/xrdp/session-alerts.log` | Alerts only (thresholds exceeded, crashes) |
| `/var/log/xrdp-sesman.log` | xrdp session manager — connection and exit events |
| `~/.xsession-errors` | GNOME session errors (per user) |