# Supabase Self-Host Installer for Unraid

Automated installer for deploying Supabase on Unraid infrastructure with a Debian 13 VM.

## What This Does

Installs and configures the official Supabase self-hosted stack with:
- Automated dependency installation (Docker, tools)
- Interactive configuration with sensible defaults
- Storage integration with Unraid array (NFS or SMB)
- Port security (localhost-only binding for sensitive services)
- SSL termination via Nginx Proxy Manager

## Architecture

```
╔══════════════════════════════════════════════════════════════════════════════════╗
║                         WATTFOURCE GRID ARCHITECTURE                             ║
║                                                                                  ║
║  ████████████████████████████████████████████████████████████████████████████    ║
║  █ UNRAID HOST (GRID NODE)                                    █                  ║
║  █ ┌─────────────────┐  ┌─────────────────────────────────┐  █                  ║
║  █ │   CACHE (SSD)   │  │        ARRAY (HDD)              │  █                  ║
║  █ │ ┌─────────────┐ │  │ ┌─────────────────────────────┐ │  █                  ║
║  █ │ │ DEBIAN VM   │ │  │ │ SUPABASE STORAGE            │ │  █                  ║
║  █ │ │ (FAST)      │ │  │ │ (REDUNDANT)                 │ │  █                  ║
║  █ │ └─────────────┘ │  │ └─────────────────────────────┘ │  █                  ║
║  █ └─────────────────┘  └─────────────────────────────────┘  █                  ║
║  ████████████████████████████████████████████████████████████████████████████    ║
║                                                                                  ║
║  NETWORK FLOW:                                                                   ║
║  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐                          ║
║  │   CLIENT    │───▶│     NPM     │───▶│     VM      │                          ║
║  │             │    │ (SSL TERM)  │    │ (KONG:8000) │                          ║
║  └─────────────┘    └─────────────┘    └─────────────┘                          ║
╚══════════════════════════════════════════════════════════════════════════════════╝
```

**Storage Strategy:**
- VM/containers/database run on Unraid cache (fast SSD/NVMe)
- User uploaded files stored on Unraid array (slower but parity-protected)
- Mimics Supabase Cloud architecture (compute fast, storage safe)

## Installation

This installer consists of **two steps**: prerequisites installation followed by Supabase deployment.

> **📋 Quick Reference**: See [QUICK-START.md](QUICK-START.md) for streamlined installation commands and troubleshooting tips.

### Key Differences from Official Guide

This installer **automates** the official Supabase self-hosting process with several enhancements:

**✅ Automated Configuration**
- Interactive setup wizard (vs manual `.env` editing)
- Automatic secret generation (vs manual secret management)
- Smart defaults and validation

**✅ Enhanced Features**
- **Storage Integration**: Built-in Unraid NFS/SMB support
- **Analytics Management**: Optional analytics with proper disabling
- **Security Options**: Port pinning for sensitive services
- **Domain Setup**: Automatic SSL-ready configuration

**🔄 Process Alignment**
- Downloads official Supabase Docker stack (same as `git clone`)
- Uses `/srv/supabase` deployment directory (vs `supabase-project`)
- Generates production-ready `.env` file (vs copying `.env.example`)
- Same `docker compose` commands for deployment

**⚠️ Minor Deviations**
- Different default values for some configurations (optimized for production)
- Enhanced SMTP setup (Resend integration vs fake mail server)
- Integrated analytics setup (vs separate configuration step)

### Core Process Alignment

The installer follows the **exact same deployment process** as the official guide:

```bash
# Official manual process:
git clone --depth 1 https://github.com/supabase/supabase
mkdir supabase-project
cp -rf supabase/docker/* supabase-project
cp supabase/docker/.env.example supabase-project/.env
cd supabase-project
docker compose pull
docker compose up -d

# This installer does the equivalent:
# ✅ Downloads Supabase Docker stack (git clone equivalent)
# ✅ Creates deployment directory (/srv/supabase)
# ✅ Copies all Docker files
# ✅ Generates .env with proper secrets
# ✅ Runs docker compose pull && docker compose up -d
```

**Same result, automated process.**

### Step 1: Prepare Your Unraid Server
- Create a Debian 13 VM on Unraid cache
- Create a `supabase-storage` share on your Unraid array
- Install Nginx Proxy Manager on Unraid host

### Step 2: Install Prerequisites (Git, Docker, Docker Compose)

**Option A: One-liner (Recommended)**
```bash
sudo bash -c 'rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.gpg 2>/dev/null; apt update && apt -y upgrade && apt install -y wget curl gpg && cd /tmp && wget --no-cache -O prerequisites-install.sh https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/prerequisites-install.sh && chmod +x prerequisites-install.sh && ./prerequisites-install.sh'
```

**Option B: Manual download**
```bash
sudo -i
wget https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/prerequisites-install.sh
chmod +x prerequisites-install.sh
./prerequisites-install.sh
```

**What the prerequisites installer does:**
- ✅ Installs Git (latest stable)
- ✅ Installs Docker Engine (20.10.0+) from official repository
- ✅ Installs Docker Compose v2 (plugin format required by Supabase)
- ✅ Installs system tools (curl, gpg, jq, openssl)
- ✅ Cleans up any broken Docker configurations
- ✅ Verifies compatibility with Supabase stack
- ✅ Creates detailed installation logs

### Step 3: Install Supabase

**Option A: One-liner (Recommended)**
```bash
sudo bash -c 'cd /tmp && wget --no-cache -O supabase-install.sh https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/supabase-install.sh && chmod +x supabase-install.sh && ./supabase-install.sh'
```

**Option B: Manual download**
```bash
sudo -i
wget https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/supabase-install.sh
chmod +x supabase-install.sh
./supabase-install.sh
```

**What the Supabase installer does:**
- ✅ Interactive configuration wizard
- ✅ Generates crypto-secure secrets
- ✅ Downloads official Supabase Docker stack
- ✅ Configures environment variables
- ✅ Sets up storage mounts (NFS/SMB)
- ✅ Deploys all containers
- ✅ Port security (localhost binding for sensitive services)

### Step 4: Follow the Interactive Prompts
The Supabase installer will guide you through:
- **Feature selection** (choose which services to enable/disable)
- Domain configuration (API & Studio)
- SMTP email setup (optional)
- Port configuration
- Security options (port pinning for sensitive services)
- Storage mount (NFS or SMB)

**Note:** Analytics/Logs service (Logflare) provides logging functionality in Supabase Studio. It requires 2GB+ RAM and can be disabled to save resources. When disabled, you won't have access to logs in the Studio dashboard.

### Alternative: Combined Installation (Both Steps)

If you prefer to run both steps together:

```bash
sudo bash -c 'rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.gpg 2>/dev/null; apt update && apt -y upgrade && apt install -y wget curl gpg && cd /tmp && wget --no-cache -O prerequisites-install.sh https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/prerequisites-install.sh && chmod +x prerequisites-install.sh && ./prerequisites-install.sh && wget --no-cache -O supabase-install.sh https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/supabase-install.sh && chmod +x supabase-install.sh && ./supabase-install.sh'
```

This will:
1. Install prerequisites (Git, Docker, Docker Compose)
2. Run the Supabase configuration wizard
3. Deploy the complete Supabase stack
### Troubleshooting

**If prerequisites installation fails:**
```bash
# Re-run the prerequisites installer
sudo bash -c 'cd /tmp && wget --no-cache -O prerequisites-install.sh https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/prerequisites-install.sh && chmod +x prerequisites-install.sh && ./prerequisites-install.sh'
```

**If Supabase installer prompts don't appear:**
```bash
# Skip the intro animation for faster/more reliable startup:
SKIP_ANIMATION=1 ./supabase-install.sh
```

**If you get port conflicts (address already in use):**
```bash
# Stop any existing Supabase containers
cd /srv/supabase
docker compose down

# Clean up Docker networks and containers
docker system prune -f
docker ps -a --filter "name=supabase" | xargs -r docker rm -f

# Re-run the installer with different ports
# Kong HTTP Port: 8001 (instead of 8000)
# Kong HTTPS Port: 8444 (instead of 8443)
```

### Step 5: Configure Nginx Proxy Manager
After installation, create two proxy hosts:
- `api.yourdomain.com` → `http://VM-IP:[KONG_HTTP_PORT]` (Enable WebSockets)
- `studio.yourdomain.com` → `http://VM-IP:3000` (Add access restrictions)

Replace:
- `VM-IP` with your VM's IP address (displayed at end of installation)
- `[KONG_HTTP_PORT]` with the Kong HTTP port you chose (default: 8000)

## Post-Installation

1. **Verify Storage Mount**
   ```bash
   df -h | grep supabase-storage
   docker compose exec storage ls -l /var/lib/storage
   ```

2. **Configure SMTP** (if skipped)
   ```bash
   cd /srv/supabase
   nano .env
   # Edit SMTP settings
   docker compose up -d auth
   ```

3. **Setup Backups**
   ```bash
   cd /srv/supabase
   mkdir -p backups
   docker compose exec -T db pg_dump -U postgres -Fc -d postgres > "backups/$(date +%F_%H-%M).dump"
   ```

4. **Update Stack**
   ```bash
   cd /srv/supabase
   docker compose pull && docker compose up -d
   ```

## Files & Locations

- **Project Directory**: `/srv/supabase`
- **Environment File**: `/srv/supabase/.env`
- **Docker Compose**: `/srv/supabase/docker-compose.yml`
- **Override Config**: `/srv/supabase/docker-compose.override.yml`
- **Storage Mount**: `/mnt/unraid/supabase-storage/<APEX_DOMAIN>`
- **Backup Files**: `/srv/supabase/.env.bak.*`

## Requirements

- Debian 13 (or compatible Linux distribution)
- Root access
- Internet connectivity
- Unraid server with NFS or SMB enabled
- Domain names pointing to your Unraid server

## Support

This is a community-maintained installer. For Supabase issues, visit: https://supabase.com/docs

## License

MIT License - Feel free to modify and distribute
