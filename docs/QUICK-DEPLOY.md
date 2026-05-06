# Quick Deploy Reference

This is the condensed version. If you get stuck anywhere, see the [full README](../README.md) or the [Troubleshooting Guide](TROUBLESHOOTING.md).

---

## Before You Start

You need:
- An Ubuntu 20.04/22.04/24.04 server with SSH access
- Port **3389** open in the server's firewall (for RDP)
- An [OpenRouter API key](https://openrouter.ai/) (free, needed for Claude Code)

---

## Deploy (3 steps)

**Step 1 — Upload the scripts** (run on your local machine):
```bash
git clone https://github.com/DarojaAI/linux-desktop-setup.git
cd linux-desktop-setup
scp deploy-desktop.sh config.sh ubuntu@YOUR_SERVER_IP:/tmp/
```

**Step 2 — Run the installer** (run on the server via SSH):
```bash
ssh ubuntu@YOUR_SERVER_IP
sudo bash /tmp/deploy-desktop.sh
```
Wait 5–15 minutes. You'll see progress messages. When it finishes, you're ready.

**Step 3 — Connect via Remote Desktop:**
- Windows: Open **Remote Desktop Connection**, enter `YOUR_SERVER_IP`
- Android: Open **Microsoft Remote Desktop**, add `YOUR_SERVER_IP`
- Username and password: your Ubuntu account credentials

---

## After Connecting

Set your API keys using the environment file (never commit this file!):

```bash
# Create your environment file from the template
cp .env.example ~/.config/desktop-seed/.env

# Edit with your actual API keys
nano ~/.config/desktop-seed/.env

# Source the environment variables
set -a && source ~/.config/desktop-seed/.env && set +a

# Verify Claude Code works
claude --version   # should print a version number
```

> **⚠️ WARNING:** Never commit `.env` to version control! It's already in `.gitignore`.

### OpenCLAW Setup (Optional)

If you installed OpenCLAW (Discord AI client), add these to your `.env` file:

```bash
# Required for OpenCLAW
OPENROUTER_API_KEY=your_openrouter_key_here
DISCORD_BOT_TOKEN=your_discord_bot_token_here
DISCORD_ALLOWLIST_IDS=your_discord_user_id
```

Get your OpenRouter key at [openrouter.ai](https://openrouter.ai/).
Get Discord tokens from the [OpenCLAW documentation](https://openclaw.app/docs).

For full OpenCLAW configuration details, see [docs/OPENCLAW_CONFIG.md](./OPENCLAW_CONFIG.md).

---

## Verify Everything Installed Correctly

```bash
sudo bash tests/validate-install.sh
```

---

## Common Fixes

| Problem | Fix |
|---------|-----|
| Blank blue screen after connecting | `sudo systemctl restart xrdp xrdp-sesman` |
| Can't connect (connection refused) | Check port 3389 is open in your server's firewall |
| `claude` command not found | Close and reopen the terminal, or run `source ~/.bashrc` |
| "OS keyring not available" in VS Code | Disconnect and reconnect via RDP |

For more, see [Troubleshooting Guide](TROUBLESHOOTING.md).

---

## Firewall Setup (AWS)

1. AWS EC2 Console → your instance → **Security** tab
2. Click the security group name → **Edit Inbound Rules** → **Add Rule**
   - Type: **RDP**, Protocol: **TCP**, Port: **3389**, Source: **My IP**
3. Save rules

## Firewall Setup (Hetzner)

1. Hetzner Cloud Console → Firewalls → your firewall
2. Add inbound rule: Protocol TCP, Port 3389, Source: `0.0.0.0/0` (or your IP)