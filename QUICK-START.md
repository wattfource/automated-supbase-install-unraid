# Quick Start Guide - Automated Supabase Installation

This guide provides **automated commands** for the official Supabase self-hosting process, with enhancements for Unraid deployment.

**🔄 Based on Official Guide**: Automates the steps from [Supabase Self-Hosting Docs](https://supabase.com/docs/guides/self-hosting/docker)

## Step 1: Prerequisites Installation (Git, Docker, Docker Compose)

This command installs Git, Docker, and Docker Compose with best practices:

```bash
sudo bash -c '
set -euo pipefail;
export DEBIAN_FRONTEND=noninteractive;
apt-get update -qq;
apt-get install -y -qq curl ca-certificates >/dev/null 2>&1;
rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.gpg 2>/dev/null || true;
cd /tmp;
curl -fsSL https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/prerequisites-install.sh -o prerequisites-install.sh;
chmod +x prerequisites-install.sh;
./prerequisites-install.sh;
'
```

### What Gets Installed

- **Git** - Latest stable version (2.x+)
- **Docker Engine** - Latest stable version (20.10.0+) from official Docker repository
- **Docker Compose** - v2 plugin format (required by Supabase)
- **System Tools** - curl, gpg, jq, openssl, ca-certificates

### Best Practices Features

✅ **Strict error handling** (`set -euo pipefail`)  
✅ **Non-interactive mode** (no hanging prompts)  
✅ **Secure downloads** (curl with SSL verification)  
✅ **Auto-cleanup** (removes broken configs)  
✅ **Idempotent** (safe to run multiple times)  
✅ **Compatibility verification** (tests Docker Compose v2)  
✅ **Full logging** (timestamped logs for debugging)  

---

## Step 2: Supabase Installation

Run the Supabase installer (includes interactive configuration):

```bash
sudo bash -c '
set -euo pipefail;
cd /tmp;
curl -fsSL https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/supabase-install.sh -o supabase-install.sh;
chmod +x supabase-install.sh;
./supabase-install.sh;
'
```

This will:
1. Run the interactive Supabase configuration wizard (with feature selection)
2. Deploy the complete Supabase stack

---

## Combined Installation (Both Steps Together)

If you prefer to run both steps in one command:

```bash
sudo bash -c '
set -euo pipefail;
export DEBIAN_FRONTEND=noninteractive;
apt-get update -qq;
apt-get install -y -qq curl ca-certificates >/dev/null 2>&1;
rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.gpg 2>/dev/null || true;
cd /tmp;
curl -fsSL https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/prerequisites-install.sh -o prerequisites-install.sh;
chmod +x prerequisites-install.sh;
./prerequisites-install.sh;
curl -fsSL https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/supabase-install.sh -o supabase-install.sh;
chmod +x supabase-install.sh;
./supabase-install.sh;
'
```

This will:
1. Install all prerequisites (Git, Docker, Docker Compose)
2. Run the interactive Supabase configuration wizard
3. Deploy the complete Supabase stack

---

## Supabase Only (If Prerequisites Already Installed)

If you've already run the prerequisites installer:

```bash
sudo bash -c '
set -euo pipefail;
cd /tmp;
curl -fsSL https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/supabase-install.sh -o supabase-install.sh;
chmod +x supabase-install.sh;
./supabase-install.sh;
'
```

---

## Manual Installation (Step-by-Step)

For more control, download and run each script separately:

```bash
# Become root
sudo -i

# Download scripts
curl -fsSL https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/prerequisites-install.sh -o prerequisites-install.sh
curl -fsSL https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/supabase-install.sh -o supabase-install.sh

# Make executable
chmod +x prerequisites-install.sh supabase-install.sh

# Run in order
./prerequisites-install.sh
./supabase-install.sh
```

---

## Verification

After prerequisites installation, verify versions:

```bash
git --version
docker --version
docker compose version
docker ps
```

Expected output:
- Git: 2.x+
- Docker: 20.10.0+
- Docker Compose: 2.x+ (plugin format)
- Docker daemon: running

---

## Logs

Installation logs are saved in the current directory:

```bash
ls -lh prerequisites-install-*.log
ls -lh supabase-install-*.log
```

View the most recent log:

```bash
tail -f prerequisites-install-*.log
```

---

## Troubleshooting

**If prerequisites check fails in Supabase installer:**
```bash
# Re-run prerequisites installer
./prerequisites-install.sh
```

**If Docker repository errors occur:**
```bash
# Manual cleanup (script does this automatically)
sudo rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.gpg
sudo apt update
```

**Skip animation in Supabase installer:**
```bash
SKIP_ANIMATION=1 ./supabase-install.sh
```

---

## Requirements

- Debian 13 VM (or compatible distribution)
- Root access (via `sudo`)
- Internet connectivity
- At least 4GB RAM recommended
- 20GB+ disk space

---

See [README.md](README.md) for complete documentation.

