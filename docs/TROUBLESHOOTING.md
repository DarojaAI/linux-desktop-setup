# Troubleshooting Guide

Find the problem you're experiencing and follow the steps. If a fix doesn't work, move to the next one in the section.

---

## I can't connect — Remote Desktop shows "connection refused" or times out

**Check 1: Is port 3389 open in your firewall?**

This is the most common cause. Your server's firewall (security group) needs to allow inbound traffic on port 3389.

- **AWS:** EC2 Console → your instance → Security tab → Edit inbound rules → add RDP (TCP 3389) from your IP
- **Hetzner:** Cloud Console → Firewalls → add inbound rule: TCP port 3389
- **DigitalOcean:** Networking → Firewalls → Inbound rules → add TCP port 3389

**Check 2: Is xrdp running on the server?**

SSH into your server and run:
```bash
systemctl status xrdp
```

If the status shows `inactive` or `failed`:
```bash
sudo systemctl start xrdp
sudo systemctl enable xrdp
```

**Check 3: Is port 3389 actually listening?**
```bash
sudo ss -tuln | grep 3389
```
If nothing is returned, xrdp isn't listening. Try restarting it:
```bash
sudo systemctl restart xrdp xrdp-sesman
```

**Check 4: Is a local firewall blocking it?**
```bash
sudo ufw status
```
If it shows `Status: active` and port 3389 isn't in the list, add it:
```bash
sudo ufw allow 3389
```

---

## I see a blank blue screen after connecting (no taskbar, no icons)

This usually means the GNOME session didn't start correctly. The most common fix:

```bash
sudo systemctl restart xrdp xrdp-sesman
```

Disconnect and reconnect via Remote Desktop after running this.

**If that doesn't work**, check the session log for clues:
```bash
tail -50 /var/log/xrdp-sesman.log
cat ~/.xsession-errors
```

**If the log shows D-Bus errors:**
The session startup script handles D-Bus initialization automatically. If it's failing, re-run the deployment to restore the correct startup script:
```bash
sudo bash /tmp/deploy-desktop.sh
```

---

## I see a black screen with a cursor, then get disconnected immediately

This is usually a GNOME session crash during startup.

**Check the session errors:**
```bash
tail -50 ~/.xsession-errors
tail -50 /var/log/xrdp-sesman.log
```

**Try restarting xrdp:**
```bash
sudo systemctl restart xrdp xrdp-sesman
```

**If the problem persists**, check whether the session startup script is intact:
```bash
cat /etc/xrdp/startwm.sh
```
The file should start with `#!/bin/bash` and contain `gnome-shell` or `gnome-session`. If it looks wrong or empty, re-run the deployment:
```bash
sudo bash /tmp/deploy-desktop.sh
```

---

## VS Code shows "OS keyring is not available for encryption"

This means the GNOME Keyring (secure password storage) isn't accessible in the current session. This usually fixes itself on the next reconnect.

**Fix: Disconnect and reconnect via Remote Desktop.** The keyring daemon starts during session initialization, so a fresh connection should clear this.

**If it keeps happening**, check whether the keyring daemon is running inside your session:
```bash
pgrep -af gnome-keyring-daemon
```
If nothing is returned, and the issue persists after reconnecting, re-run the deployment to restore keyring setup:
```bash
sudo bash /tmp/deploy-desktop.sh
```

---

## Claude Code shows an error or doesn't work

**Check 1: Is your API key set?**
```bash
echo $OPENROUTER_API_KEY
```
If this prints nothing, the key isn't set. Add it:
```bash
echo 'export OPENROUTER_API_KEY="your_key_here"' >> ~/.bashrc
source ~/.bashrc
```

**Check 2: Is Claude Code installed?**
```bash
claude --version
```
If you get "command not found", try:
```bash
source ~/.bashrc
```
If still not found, re-run the deployment to reinstall it.

---

## High memory usage or the desktop feels very slow

**Check what's using memory:**
```bash
ps aux --sort=-%mem | head -10
```

**View memory trends from the monitor:**
```bash
bash scripts/analyze-session-logs.sh --memory
```

**Common causes and fixes:**
- GNOME Shell can accumulate memory over long sessions — disconnect and reconnect to get a fresh session
- Browser tabs are memory-heavy — close unused Chromium tabs
- If memory is consistently above 80%, consider upgrading your server's RAM or switching to a lighter desktop (XFCE uses significantly less memory than GNOME)

---

## The crash monitor service isn't running

```bash
systemctl status xrdp-session-monitor.service
```

If it shows `inactive` or `failed`:
```bash
sudo systemctl restart xrdp-session-monitor.service
```

To check what went wrong:
```bash
journalctl -u xrdp-session-monitor.service -n 50
```

---

## After running the deployment script, nothing changed on the server

This can happen if the script was run without `sudo`, or if the script from `/tmp/` was out of date.

**Always deploy with:**
```bash
sudo bash /tmp/deploy-desktop.sh
```

If you updated the scripts in the repository, make sure to re-upload them before running:
```bash
scp deploy-desktop.sh ubuntu@YOUR_SERVER_IP:/tmp/
scp config.sh ubuntu@YOUR_SERVER_IP:/tmp/
ssh ubuntu@YOUR_SERVER_IP
sudo bash /tmp/deploy-desktop.sh
```

---

## Running a full validation check

After any deployment or change, you can run a comprehensive check of everything:

```bash
sudo bash tests/validate-install.sh
```

This checks that all services are running, all tools are installed, and configuration files are in place.

---

## Useful log locations

| Log File | What to look for |
|----------|-----------------|
| `/var/log/xrdp-sesman.log` | RDP session errors and connection attempts |
| `/var/log/xrdp/session-monitor.log` | Health check history |
| `/var/log/xrdp/session-alerts.log` | Threshold alerts (memory, CPU) |
| `~/.xsession-errors` | GNOME session startup errors |
| `/tmp/deploy-desktop-*.log` | Output from the deployment script |

---

## Known Limitations

These are by design and currently have no fix:

- **Wayland not supported** — the server uses Xvnc (X11 only); GNOME runs in X11 mode
- **Single user only** — the deployment is configured for one desktop user
- **No audio over RDP** — sound does not forward through the remote desktop connection
- **No printer sharing** — printer redirection is not set up