# Technical Reference

This document is for developers, contributors, and operators who want to understand the internals — architecture decisions, session startup sequence, component integration, and known issues.

For setup instructions, see the [README](../README.md). For troubleshooting, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

---

## Architecture Overview

### Session Startup Sequence

When a user connects via RDP, this is the exact sequence of events:

```
User connects (Microsoft Remote Desktop → server IP:3389)
  ↓
xrdp receives the connection on port 3389
  ↓
xrdp-sesman launches /etc/xrdp/startwm.sh
  ↓
startwm.sh sets environment variables:
  - XDG_SESSION_TYPE=x11 (force X11, not Wayland)
  - GDK_BACKEND=x11
  - GNOME_SHELL_WAYLANDRESTART=false
  - ulimit -v 2097152 (2 GB per-process memory limit)
  ↓
startwm.sh registers EXIT trap (crash logging handler)
  ↓
dbus-launch starts a D-Bus session
  (D-Bus is the inter-process message bus desktop apps use to communicate)
  ↓
gnome-keyring-daemon starts inside the D-Bus session
  (must be inside D-Bus context — this is why credential storage works)
  ↓
gnome-shell starts the GNOME desktop
  (inherits all environment variables set above)
  ↓
xrdp-session-monitor watches in the background (30-second intervals)
```

### Why `gnome-shell` and not `gnome-session`

On Ubuntu 24.04, `gnome-session` has compatibility issues with xrdp — it crashes silently during session initialization. Starting `gnome-shell` directly bypasses this. This was discovered empirically on Hetzner hardware with Ubuntu 24.04.4.

### Why D-Bus must be initialized first

GNOME components communicate through D-Bus. If D-Bus isn't running when GNOME starts, components can't talk to each other — you get a blank blue screen (the desktop loads but can't render properly). Using `dbus-launch` ensures the session bus is running before any GNOME process starts.

### Why keyring must start inside the D-Bus session

`gnome-keyring-daemon` exports environment variables (like `DBUS_SESSION_BUS_ADDRESS`) that child processes need to find the keyring. If the daemon is started before D-Bus, it can't export these variables into the session, and apps see "OS keyring not available." Starting it inside `dbus-launch` ensures all child processes inherit the correct environment.

---

## Script Structure

```
deploy-desktop.sh          Main deployment script (~1200 lines)
config.sh                  Component declarations (shared by deploy + tests)
etc/xrdp/
  startwm.sh               Session startup script (keyring + env + crash handler)
scripts/
  session-monitor.sh       Monitoring service installer/manager
  analyze-session-logs.sh  Log analysis tool (4 modes)
tests/
  validate-install.sh      Post-deployment verification
docs/                      Documentation (this file is in here)
```

### deploy-desktop.sh structure

```
check_root()               Verify running as root
detect_ubuntu_version()    Set version-specific variables
update_system()            apt-get update + upgrade

install_gnome()            GNOME desktop packages
configure_xwrapper()       X server wrapper configuration
install_xrdp()             xrdp + Xvnc configuration

install_vscode()           VS Code (Microsoft repo)
install_claude_code()      Claude Code (npm global)
install_openrouter()       OpenRouter CLI
install_chromium()         Chromium browser
install_github_cli()       GitHub CLI (gh)
install_bun()              Bun JavaScript runtime

setup_environment()        Environment variables, .bashrc
configure_mcp_servers()    MCP server configuration for Claude
create_desktop_shortcuts() Desktop icons

setup_keyring()            gnome-keyring packages + PAM integration
setup_monitoring()         Session monitor service install + enable
setup_gnome_extensions()   Cascade Windows extension

show_summary()             Post-deployment status report

main()                     Orchestrates all of the above in order
```

**Idempotency:** Every `install_*` function checks whether the component is already installed before doing anything. This means you can run `deploy-desktop.sh` multiple times without side effects.

---

## Component Integration

### How `setup_keyring()` works

1. Installs `gnome-keyring`, `libsecret-1-0`, `libpam-gnome-keyring`
2. Verifies installation success
3. The actual daemon startup is handled in `startwm.sh`, not here

### How `setup_monitoring()` works

1. Copies `scripts/session-monitor.sh` to `/tmp/` on the remote machine
2. Runs `session-monitor.sh --enable` which:
   - Creates the systemd service unit file
   - Writes the monitoring script to `/usr/local/bin/xrdp-session-monitor`
   - Writes the config file to `/var/lib/xrdp/session-monitor-config.sh`
   - Enables and starts the service

### How `startwm.sh` handles crashes

A bash EXIT trap is registered at startup:
```bash
trap 'log_crash_context $? "${BASH_LINENO[0]}"' EXIT
```

`log_crash_context()` runs on any exit (clean or crash) and writes:
- Exit code and signal number
- Timestamp
- Available memory at exit
- Top 5 memory-consuming processes

This data goes to `~/.xsession-errors` and is also readable by the monitoring service.

---

## Profile Script Compatibility

Ubuntu's `/etc/profile` and `~/.profile` sometimes use unbound variable references. Combined with `set -euo pipefail` in `startwm.sh`, this would cause the session to exit immediately.

The fix is to temporarily relax strict mode when sourcing profiles:
```bash
set +u
[ -r /etc/profile ] && . /etc/profile 2>/dev/null || true
[ -r "$HOME/.profile" ] && . "$HOME/.profile" 2>/dev/null || true
set -u
```

---

## Tested Environment

| Component | Details |
|-----------|---------|
| Provider | Hetzner Cloud |
| Virtualization | QEMU/KVM |
| OS | Ubuntu 24.04.4 LTS (Noble Numbat) |
| RAM | 8 GB |
| CPU | 4 vCPU |
| Storage | SSD (system disk) |

Also tested on Ubuntu 20.04 and 22.04. Ubuntu 24.04 required the `gnome-shell` workaround described above.

---

## Known Issues and Workarounds

### Wayland not supported
xrdp uses Xvnc which only supports X11. GNOME must be forced to X11 mode via environment variables:
```bash
export XDG_SESSION_TYPE=x11
export GDK_BACKEND=x11
export GNOME_SHELL_WAYLANDRESTART=false
```
These are set in `startwm.sh`.

### gnome-session crashes on Ubuntu 24.04 under xrdp
`gnome-session` initializes components that expect a physical display, and fails silently under Xvnc. Starting `gnome-shell` directly avoids this. Investigated via `~/.xsession-errors` showing the session exiting with SIGKILL immediately after `gnome-session` launched.

### Unbound variable in profile scripts
Ubuntu's default profiles reference `$BASH_VERSINFO` and other variables that aren't set in all contexts. The `set +u` / `set -u` bracket around profile sourcing handles this.

### Console session conflict
If someone is logged in on the physical console (unlikely for a cloud VM), the RDP session may have display conflicts. This is not addressed in the current deployment.

---

## Coding Standards

### Bash style
- `#!/bin/bash` at top of every script
- `set -euo pipefail` early in each script
- Quote all variables: `"$var"` not `$var`
- `[[ ]]` for conditionals (not `[ ]`)
- `lowercase_underscored` function names
- 4-space indentation

### Error handling
```bash
if ! some_command; then
    log_error "Descriptive message about what failed and why"
    return 1
fi
```

### Logging
```bash
log_info "Starting X"    # success/progress (green)
log_warn "X had issue"   # non-fatal warning (yellow)
log_error "X failed"     # fatal error (red)
```

### GPG keys
Use `/etc/apt/keyrings/` (the modern approach) rather than `apt-key`, which is deprecated.

---

## Development Workflow

1. Make changes locally
2. Test on a dev VM
3. Commit with a descriptive message explaining *why* not just *what*
4. Push to main

**Rule:** When a bug is found on a running VM, fix the deployment scripts in the repository — not just the remote machine. The fix must benefit future deployments.

### Syntax check before committing
```bash
bash -n deploy-desktop.sh
```

### Quick function inventory
```bash
grep -n "^[a-z].*() {" deploy-desktop.sh
```

---

## Adding Features

Good candidates:
- Features that improve core mission (reliable RDP desktop access)
- Reliability and crash recovery improvements
- Security enhancements

Avoid:
- Tools that aren't related to development or the desktop environment
- Features that conflict with RDP or GNOME
- Heavy background processes that consume significant resources
- Anything that breaks idempotency