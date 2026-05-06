# GNOME Keyring Guide

## What Is the Keyring?

The keyring is a secure password vault built into GNOME. Applications like VS Code use it to store sensitive data — GitHub tokens, API keys, saved passwords — so they don't have to ask you every time.

On a normal Ubuntu server with no desktop, the keyring doesn't exist. When VS Code tries to use it, you see:

```
OS keyring is not available for encryption
```

This deployment fixes that by starting the keyring daemon at the right point in the session startup sequence, before any applications launch. You don't need to configure anything — it just works.

---

## How It Works

When you connect via RDP, the session startup sequence is:

1. `startwm.sh` starts running
2. A **D-Bus session** is initialized (the messaging system desktop apps use to talk to each other)
3. **`gnome-keyring-daemon` starts** inside the D-Bus session
4. GNOME desktop loads — all apps inherit access to the keyring automatically

The key detail is step 3: the keyring daemon must start *inside* the D-Bus session, not before it. That's what this deployment does correctly.

---

## Checking That It's Working

```bash
# Should show the daemon process
pgrep -af gnome-keyring-daemon

# Should show a non-empty address (means D-Bus is active)
echo $DBUS_SESSION_BUS_ADDRESS
```

If `echo $DBUS_SESSION_BUS_ADDRESS` returns nothing, the session didn't start correctly. Disconnect and reconnect via Remote Desktop.

---

## Storing and Retrieving Secrets (Command Line)

The `secret-tool` command lets you store and retrieve secrets from the keyring.

**Store a secret:**
```bash
secret-tool store --label="My API Key" service myapp account myuser
# You'll be prompted to enter the secret value
```

**Retrieve a secret:**
```bash
secret-tool lookup service myapp account myuser
```

**Delete a secret:**
```bash
secret-tool clear service myapp account myuser
```

---

## Troubleshooting

### "OS keyring is not available" keeps appearing

**Fix: Disconnect and reconnect via Remote Desktop.**

This resets the session and restarts the keyring daemon. The error should not appear again in the new session.

If it persists after reconnecting, check whether the daemon is running:
```bash
pgrep -af gnome-keyring-daemon
```

If nothing is returned, the keyring daemon isn't starting. Try re-running the deployment:
```bash
sudo bash /tmp/deploy-desktop.sh
```

### Keyring errors after a long session

If you see keyring errors after working for several hours, disconnecting and reconnecting typically resolves it. The keyring runs in memory for the duration of a session; a fresh connection starts it cleanly.

---

## Security Notes

- The keyring is unlocked automatically when you log in via RDP (your login password is the master password)
- Credentials are stored encrypted in `~/.local/share/keyrings/`
- The keyring is separate per user — other users on the same server cannot access your stored secrets
- If you log out or disconnect, applications lose access to the keyring until you reconnect

---

## SSH Key Management

The keyring also stores SSH key passphrases, so you don't have to type them every time:

```bash
ssh-add ~/.ssh/id_ed25519
# Enter your passphrase once; it's stored in the keyring for the session
```

To verify what keys are loaded:
```bash
ssh-add -l
```