# Using Your Remote Desktop

**OpenCLAW Version:** v2026.04.11 (MiniMax compatible)

This guide assumes you've already deployed the desktop and can connect via RDP. If you haven't done that yet, start with the [Quick Deploy](QUICK-DEPLOY.md) guide.

---

## Connecting to Your Desktop

### From Windows

1. Press **Windows + S** and search for **Remote Desktop Connection**
2. In the **Computer** field, type your server's IP address
3. Click **Connect**
4. Enter your Ubuntu username and password when prompted
5. The GNOME desktop should appear within a few seconds

> **Tip:** Save the connection so you don't have to type the IP each time. In Remote Desktop Connection, click **Show Options** → **Save As** before connecting.

### From Android Tablet

1. Install **[Microsoft Remote Desktop](https://play.google.com/store/apps/details?id=com.microsoft.rdc.androidx)** from the Google Play Store
2. Open the app and tap the **+** button
3. Select **Add PC**
4. Enter your server's IP address
5. Tap **Connect** and enter your Ubuntu credentials

Landscape mode works best. If you need a keyboard, enable the on-screen keyboard: **Settings → Accessibility → Keyboard → On-Screen Keyboard**.

---

## First Things to Do After Connecting

### 1. Open a terminal

Right-click anywhere on the desktop and select **Open Terminal**, or press **Ctrl+Alt+T**.

### 2. Set your OpenRouter API key

This is what powers Claude Code (the AI assistant). You only need to do this once:

```bash
echo 'export OPENROUTER_API_KEY="your_api_key_here"' >> ~/.bashrc
source ~/.bashrc
```

Replace `your_api_key_here` with your actual key from [openrouter.ai](https://openrouter.ai/).

### 3. Verify everything is working

```bash
claude --version      # should print a version number
code --version        # should print VS Code version
gh --version          # should print GitHub CLI version
openclaw --version    # should print OpenCLAW version
chromium-browser      # should open the browser
```

---

## Using [VS Code](https://code.visualstudio.com/)

[VS Code](https://code.visualstudio.com/) is a full code editor with support for extensions, debugging, and an integrated terminal.

**Open it from the desktop** by clicking the VS Code icon, or **from a terminal**:

```bash
code .               # open the current folder as a project
code ~/my-project    # open a specific folder
code myfile.py       # open a single file
```

**First time setup tips:**
- Sign into your GitHub account: click the person icon at the bottom-left → **Turn on Settings Sync**
- Install extensions you need: press **Ctrl+Shift+X** to open the Extensions panel
- Open a terminal inside VS Code: press **Ctrl+`** (backtick)

---

## Using [Claude Code](https://claude.ai/code) (AI assistant)

[Claude Code](https://claude.ai/code) is an AI coding assistant that runs in the terminal. It can read your code, answer questions, write functions, find bugs, and explain things.

**Start an interactive session:**
```bash
claude
```

You'll see a prompt where you can type questions like:
- "Explain what this function does"
- "Write a Python function that reads a CSV file"
- "Why is this code throwing a TypeError?"

**Ask a quick one-shot question:**
```bash
claude "what does the grep command do?"
claude "show me how to list files in Python"
```

**Use it inside a project folder** — Claude Code will read your files and give context-aware answers:
```bash
cd ~/my-project
claude "what does this codebase do?"
```

> **Note:** Claude Code requires your `OPENROUTER_API_KEY` to be set (see Step 2 above).

---

## Using [GitHub CLI](https://cli.github.com/)

[GitHub CLI](https://cli.github.com/) (`gh`) lets you manage your GitHub repositories, pull requests, and issues from the terminal — without needing a browser.

**First time: log in to GitHub**

```bash
gh auth login
```

Follow the prompts:
1. Select **GitHub.com**
2. Select **HTTPS**
3. Select **Login with a web browser**
4. A code will appear in the terminal — copy it
5. A browser window will open (or open the URL shown) — paste the code there
6. Authorize the app

**Common commands:**

```bash
gh repo clone owner/repo-name   # download a repository
gh repo list                    # list your repositories
gh pr list                      # see open pull requests
gh pr create                    # create a new pull request
gh issue list                   # see open issues
```

---

## Using [OpenCLAW](https://openclaw.app/)

[OpenCLAW](https://openclaw.app/) is installed as a global npm package and lets you connect to remote Discord instances from the terminal.

**Start OpenCLAW:**
```bash
openclaw
```

**Check it is installed:**
```bash
openclaw --version
```

> **Note:** OpenCLAW requires Node.js, which is installed automatically during deployment. If the command is not found, try `source ~/.bashrc` or open a new terminal.

### OpenCLAW Configuration

Default settings are deployed from `config/openclaw-defaults.json` during setup. The config file is located at `~/.openclaw/openclaw.json`.

**Key settings:**
- `reserveTokensFloor: 20000` - Keep 20k tokens for context
- `maxConcurrent: 4` - Run up to 4 concurrent agents
- `compaction.mode: safeguard` - Only compact when necessary

To view your current config:
```bash
cat ~/.openclaw/openclaw.json
```

To update defaults, edit `config/openclaw-defaults.json` in the repo and redeploy.

---

## Using [Chromium Browser](https://www.chromium.org/chromium-projects/)

[Chromium](https://www.chromium.org/chromium-projects/) is the open-source version of Chrome. It works just like Chrome.

**Open it from the desktop** by clicking the Chromium icon, or **from a terminal:**

```bash
chromium-browser
```

> **If the browser is slow:** Chromium over RDP can feel sluggish on slow internet connections. For browsing-heavy work, consider keeping a local browser open for general use and using the remote Chromium only when you need it to be on the server (e.g. to authenticate with a service).

---

## Using Terraform and Terragrunt

### Terraform
Terraform is installed and ready to use. Run `terraform --version` to verify:

```bash
terraform --version
```

### Terragrunt
Terragrunt is also installed. It's a thin wrapper that provides extra tools for working with Terraform:

```bash
terragrunt --version
```

### Getting Started with IaC
1. Create a directory for your Terraform code: `mkdir ~/terraform && cd ~/terraform`
2. Create a `.tf` file (e.g., `main.tf`)
3. Run `terraform init` to initialize providers
4. Run `terraform plan` to preview changes
5. Run `terraform apply` to create resources

### Cloud Provider Credentials
For AWS, Azure, or GCP, you'll need to configure credentials:
- **AWS:** `aws configure` (requires AWS CLI)
- **Azure:** `az login` (requires Azure CLI)
- **GCP:** `gcloud auth login` (requires Google Cloud SDK)

---

## Desktop Tips

### Keyboard shortcuts
| Shortcut | What It Does |
|----------|-------------|
| **Super** (Windows key) | Opens the app launcher / overview |
| **Ctrl+Alt+T** | Opens a new terminal |
| **Alt+F4** | Closes the current window |
| **Super+H** | Hides (minimizes) the current window |

### Workspaces (virtual desktops)
GNOME supports multiple workspaces so you can organize your windows:
- **Super+Page Up / Page Down** — switch workspaces
- **Super+Shift+Page Up / Page Down** — move the current window to another workspace

### Window arrangement
The **Cascade Windows** extension is pre-installed. You can access it from the GNOME Extensions menu to tile or organize your windows.

### On-screen keyboard (Android tablet)
Go to **Settings → Accessibility → Keyboard → On-Screen Keyboard** and toggle it on.

---

## Security Recommendations

1. **Use a strong password** for your Ubuntu account — it's what protects RDP access
2. **Restrict port 3389 to your IP** in your server's firewall, rather than opening it to the world
3. **Use SSH keys instead of passwords** for server access — see the [SSH Setup Guide](ssh-setup-guide.md)
4. **Keep the system updated** periodically:
   ```bash
   sudo apt update && sudo apt upgrade
   ```

---

## Getting Help

If something isn't working as expected:

- **Tools not found:** Run `source ~/.bashrc` or close and reopen the terminal
- **RDP problems:** See [Troubleshooting Guide](TROUBLESHOOTING.md)
- **Crash or performance issues:** See [Crash Recovery Guide](CRASH-RECOVERY.md)