# linux-desktop-setup

Install a full Linux desktop environment on any VM. Designed to work with [terraform-hcloud-linux-vm](https://github.com/DarojaAI/terraform-hcloud-linux-vm) or any Linux VM with SSH access.

**Status:** Production-ready. Tested on Ubuntu 22.04 and 24.04 on Hetzner Cloud VMs.

---

## Table of Contents

- [What Problem Does This Solve?](#what-problem-does-this-solve)
- [Disclaimer](#disclaimer)
- [Tested On](#tested-on)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Quick Start](#quick-start)
  - [Using with terraform-hcloud-linux-vm](#using-with-terraform-hcloud-linux-vm)
  - [Connecting to the Desktop](#connecting-to-the-desktop)
- [What Gets Installed](#what-gets-installed)
- [Project Structure](#project-structure)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)
- [Contributing & License](#contributing--license)

---

## What Problem Does This Solve?

Provisioning a VM is only half the battle. Once you have a bare Linux server, you still need to install GNOME, xrdp for RDP access, VS Code, development tools, and various utilities. This script automates all of that in one `deploy-desktop.sh` run.

```
terraform apply (terraform-hcloud-linux-vm) → bare VM
        ↓
deploy-desktop.sh (this repo) → full desktop environment
        ↓
Connect via RDP → ready-to-use Linux desktop
```

---

## Disclaimer

**Use at your own risk.** This script modifies system packages and configuration on the target VM.

- Always review scripts before running with sudo
- The script is idempotent — safe to re-run if something goes wrong
- The [MIT license](LICENSE) applies: this software is provided "as is", without warranty of any kind

---

## Tested On

Validated against:

| Component | Version |
|---|---|
| OS | Ubuntu 22.04 LTS, Ubuntu 24.04 LTS |
| VM | Hetzner Cloud VM (cpx41, cpx51, cax41) |
| Terraform | >= 1.0 with hetznercloud/hcloud >= 1.47 |
| Desktop | GNOME 44+, xrdp |

---

## Getting Started

### Prerequisites

- A running Linux VM with SSH access and sudo privileges
- SSH key authentication configured
- At least 2 vCPUs and 4 GB RAM recommended

### Quick Start

**Step 1 — SSH into the VM**

```bash
ssh root@<your-vm-ip>
```

**Step 2 — Clone and run**

```bash
git clone https://github.com/DarojaAI/linux-desktop-setup.git
cd linux-desktop-setup
sudo bash deploy-desktop.sh
```

The script takes 5–15 minutes depending on VM speed and package download times.

**Step 3 — Connect via RDP**

After the script completes, connect using your RDP client:

- Server: `<vm-ip-address>`
- Port: `3389`
- Username: `desktopuser`
- Password: your Ubuntu user's password

### Using with terraform-hcloud-linux-vm

**Full end-to-end setup:**

```bash
# 1. Clone the VM module
git clone https://github.com/DarojaAI/terraform-hcloud-linux-vm.git
cd terraform-hcloud-linux-vm

# 2. Create main.tf with your values
cat > main.tf << 'EOF'
module "linux_vm" {
  source  = "DarojaAI/linux-vm/hcloud"
  version = "1.0.0"

  hcloud_token = "your_token_here"
  server_name  = "my-desktop"
  location     = "fsn1"
  server_type  = "cpx41"
  image        = "ubuntu-22.04"

  hetzner_ssh_key_name = "my-ssh-key"
}

output "connection_info" {
  value = module.linux_vm.connection_info
}
EOF

# 3. Provision the VM
terraform init
terraform apply

# 4. Note the IP, then SSH and run the desktop setup
ssh root@<vm-ip>
git clone https://github.com/DarojaAI/linux-desktop-setup.git
cd linux-desktop-setup
sudo bash deploy-desktop.sh
```

### Connecting to the Desktop

**From Windows:**
- Open **Remote Desktop Connection** (search in Start menu)
- Computer: `<ipv4_address>`
- Username: `desktopuser`
- Click Connect, enter your Ubuntu password when prompted

**From Android:**
- Install **Microsoft Remote Desktop** from Google Play Store
- Add a new PC: enter the server IP
- Save and connect with your Ubuntu credentials

**From macOS:**
- Use **Microsoft Remote Desktop** from the App Store
- Same as above — IP, username, password

---

## What Gets Installed

The script installs and configures:

| Category | Packages/Components |
|---|---|
| **Desktop** | GNOME 44+, gdm3, xfce4-terminal, gnome-tweaks |
| **Remote Access** | xrdp, xorgxrdp |
| **Development** | build-essential, git, curl, wget, unzip, terminator |
| **VS Code** | Latest VS Code from Microsoft's repository |
| **AI Tools** | Node.js, npm, Claude CLI |
| **Monitoring** | htop, bpytop, bashtop, tmux |
| **Python** | python3, pip, venv |
| **Additional** | Chrome, FileZilla, Postman, Slack |

For full details, see the deploy scripts in `scripts/deploy/`:
- `system.sh` — core system packages
- `dev-tools.sh` — development tools
- `ai-tools.sh` — AI/CLI tooling
- `desktop-environment.sh` — GNOME and xrdp
- `configure.sh` — post-install configuration

---

## Project Structure

```
linux-desktop-setup/
├── deploy-desktop.sh              ← Entry point (run with sudo)
├── scripts/
│   └── deploy/
│       ├── lib.sh                 ← Shared functions
│       ├── system.sh              ← Core packages
│       ├── dev-tools.sh           ← Development tools
│       ├── ai-tools.sh            ← AI tooling (Node, Claude CLI)
│       ├── desktop-environment.sh← GNOME + xrdp
│       ├── configure.sh           ← Post-install config
│       ├── aggregator.sh          ← Combines all deploy scripts
│       └── openclaw/
│           ├── install.sh         ← OpenClaw agent installation
│           ├── config.sh          ← OpenClaw configuration
│           └── governance.sh      ← Agent governance settings
└── README.md
```

The `scripts/remote/` directory contains utilities for remote configuration:
- `ensure-repo.sh` — ensure this repo is present on the VM
- `configure-openclaw-agent.sh` — configure OpenClaw after setup

---

## Configuration

### Environment Variables

| Variable | Description | Default |
|---|---|---|
| `DESKTOP_USER` | Username for desktop access | `desktopuser` |
| `RDP_PORT` | RDP listen port | `3389` |
| `DISPLAY` | Display manager | `:0` |

### Customizing the Deploy

Edit `deploy-desktop.sh` or individual scripts in `scripts/deploy/` to customize what gets installed. Each deploy script is standalone and can be run independently.

For example, to skip AI tools:

```bash
sudo bash scripts/deploy/ai-tools.sh  # or just skip this line in deploy-desktop.sh
```

---

## Troubleshooting

### xrdp not connecting

1. Verify xrdp is running:
   ```bash
   systemctl status xrdp
   ```

2. Check that port 3389 is open:
   ```bash
   ss -tlnp | grep 3389
   ```

3. Try connecting with the local user (not root)

### Black screen after RDP

This is usually a GNOME session issue. Try:
1. Log out and reconnect
2. If that fails, switch to xfce4 by creating `~/.xsession` with:
   ```bash
   echo "xfce4-session" > ~/.xsession
   ```

### Script fails mid-way

The script is idempotent. Re-run `sudo bash deploy-desktop.sh` — it will pick up where it left off and fix any incomplete installations.

### VS Code not launching

Check if it's installed:
```bash
which code
```

If not, run:
```bash
sudo bash scripts/deploy/dev-tools.sh
```

---

## Contributing & License

### Module Structure

```
linux-desktop-setup/          ← Layer 2: Desktop environment setup
├── deploy-desktop.sh         ← main entry point
├── scripts/deploy/            ← individual install scripts
│   ├── lib.sh
│   ├── system.sh
│   ├── dev-tools.sh
│   ├── ai-tools.sh
│   ├── desktop-environment.sh
│   ├── configure.sh
│   ├── aggregator.sh
│   └── openclaw/             ← Layer 3: OpenClaw agent (can work independently)
└── README.md
```

This repo is **Layer 2** in a three-layer system:
- **Layer 1** — Infrastructure: [terraform-hcloud-linux-vm](https://github.com/DarojaAI/terraform-hcloud-linux-vm)
- **Layer 2** — Desktop environment: This repo
- **Layer 3** — Agent integration: OpenClaw configuration (included in scripts/openclaw/)

Layer 3 (OpenClaw) can be used independently of Layer 2 if you already have a desktop environment and just want the agent setup.

### Contributing

When updating:
- Test on a real VM (not docker or WSL)
- Run `shellcheck` on any new bash scripts
- Idempotency: ensure scripts can be re-run without breaking

---

## License

MIT — see [LICENSE](LICENSE) for the full text.