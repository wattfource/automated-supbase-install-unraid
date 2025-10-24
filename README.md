# Supabase Self-Host Installer for Unraid

Automated installer for deploying Supabase on Unraid infrastructure with a Debian 13 VM.

## What This Does

Installs and configures the official Supabase self-hosted stack with:
- Automated dependency installation (Docker, tools)
- Interactive configuration with sensible defaults
- Storage integration with Unraid array (NFS or SMB)
- Port security (localhost-only binding for sensitive services)
- SSL-ready configuration for reverse proxy setup

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
║  ┌─────────────┐    ┌─────────────┐                                           ║
║  │   CLIENT    │───▶│     VM      │                                           ║
║  │             │    │ (KONG:8000) │                                           ║
║  └─────────────┘    └─────────────┘                                           ║
╚══════════════════════════════════════════════════════════════════════════════════╝
```

**Storage Strategy:**
- VM/containers/database run on Unraid cache (fast SSD/NVMe)
- User uploaded files stored on Unraid array (slower but parity-protected)
- Mimics Supabase Cloud architecture (compute fast, storage safe)

## Installation

This installer consists of **two steps**: prerequisites installation followed by Supabase deployment.

**📁 Files included:**
- `prerequisites-install.sh` - Installs Git, Docker, and Docker Compose
- `supabase-install.sh` - Interactive Supabase configuration and deployment
- `QUICK-START.md` - Quick reference guide
- `README.md` - Complete documentation

> **📋 Quick Reference**: See [QUICK-START.md](QUICK-START.md) for streamlined installation commands and troubleshooting tips.

### Key Differences from Official Guide

This installer **automates** the official Supabase self-hosting process with several enhancements:

**✅ Automated Configuration**
- Interactive setup wizard (vs manual `.env` editing)
- Automatic secret generation (vs manual secret management)
- Smart defaults and validation

**✅ Enhanced Features**
- **Storage Integration**: Built-in Unraid NFS/SMB support
- **Security Options**: Port pinning for sensitive services
- **Domain Setup**: Automatic SSL-ready configuration
- **Always-Enabled Analytics**: Studio dashboard and monitoring included by default
- **Complete Feature Set**: All Supabase services working out-of-the-box

**🔄 Process Alignment**
- Downloads official Supabase Docker stack (same as `git clone`)
- Uses `/srv/supabase` deployment directory (vs `supabase-project`)
- Generates production-ready `.env` file (vs copying `.env.example`)
- Same `docker compose` commands for deployment

**⚠️ Minor Deviations**
- Different default values for some configurations (optimized for production)
- Enhanced SMTP setup (Resend integration vs fake mail server)
- Always-enabled analytics (vs optional in some setups)

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

**Same result, automated process with full functionality enabled.**

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

### Step 4: Follow the Interactive Prompts
The Supabase installer will guide you through:
- **Feature selection** (choose which optional services to enable/disable)
- Domain configuration (API & Studio)
- SMTP email setup (optional)
- Port configuration
- Security options (port pinning)
- Storage mount (NFS or SMB)

**✅ Analytics & Monitoring**: Always enabled - provides Studio dashboard, API monitoring, and debugging capabilities essential for managing your Supabase instance.

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

**If you get Docker repository errors:**
```bash
# Manual cleanup (scripts do this automatically):
sudo rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.gpg
sudo apt update
# Then run the prerequisites installer again
```

### Step 5: Configure Reverse Proxy (Optional)
For SSL termination and domain access, configure Nginx Proxy Manager or similar:

**Create two proxy hosts:**
- `api.yourdomain.com` → `http://VM-IP:8000` (Enable WebSockets)
- `studio.yourdomain.com` → `http://VM-IP:3000`

Replace `VM-IP` with your VM's IP address (displayed at end of installation)

**Note:** Reverse proxy is optional - you can access services directly via IP:port

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

## Managing Your Supabase Installation

All Docker commands must be run from the Supabase directory:
```bash
cd /srv/supabase
```

### Basic Operations

**Check Status**
```bash
docker compose ps
# Shows all containers and their health status
```

**View Logs**
```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f auth
docker compose logs -f db
docker compose logs -f kong
docker compose logs -f storage

# Last 100 lines
docker compose logs --tail=100
```

**Start All Services**
```bash
docker compose up -d
# -d runs in background (detached mode)
```

**Stop All Services**
```bash
docker compose stop
# Graceful shutdown (preserves data)
```

**Stop and Remove Containers**
```bash
docker compose down
# Stops and removes containers (data in volumes is preserved)

docker compose down -v
# ⚠️ WARNING: Removes containers AND volumes (deletes all data!)
```

**Restart All Services**
```bash
docker compose restart
```

**Restart Specific Service**
```bash
docker compose restart auth
docker compose restart kong
docker compose restart storage
```

### Updating Supabase

**Pull Latest Images**
```bash
cd /srv/supabase
docker compose pull
docker compose up -d
# Downloads new versions and recreates containers
```

**Check for Updates**
```bash
docker compose pull --dry-run
# Shows which images would be updated
```

### Troubleshooting Commands

**View Container Resource Usage**
```bash
docker stats
# Shows CPU, memory, network usage in real-time
```

**Inspect Container Details**
```bash
docker compose ps
docker inspect <container-name>
```

**Access Container Shell**
```bash
docker compose exec db bash
docker compose exec storage sh
# Exit with: exit
```

**Run Database Query**
```bash
docker compose exec -T db psql -U postgres -d postgres -c "SELECT version();"
```

**Verify Storage Mount**
```bash
docker compose exec storage ls -lah /var/lib/storage
```

**Check Port Bindings**
```bash
docker compose ps
# Or system-wide:
sudo ss -tulpn | grep docker
```

**Force Recreate Containers**
```bash
docker compose up -d --force-recreate
# Useful if configuration changes aren't applying
```

**Remove Unused Images**
```bash
docker image prune -a
# Frees up disk space from old images
```

### Common Issues

**Port Already in Use**
```bash
# Find what's using the port
sudo ss -tulpn | grep :8000
sudo ss -tulpn | grep :3000

# Stop conflicting service or change Supabase ports in .env
```

**Service Won't Start**
```bash
# Check specific service logs
docker compose logs <service-name>

# Check if database is healthy
docker compose ps db

# Restart problematic service
docker compose restart <service-name>
```

**Database Connection Issues**
```bash
# Verify database is running and healthy
docker compose ps db

# Check database logs
docker compose logs db

# Test connection
docker compose exec db psql -U postgres -d postgres -c "SELECT 1;"
```

**Out of Disk Space**
```bash
# Check Docker disk usage
docker system df

# Remove unused containers, images, volumes
docker system prune -a --volumes
# ⚠️ WARNING: This removes ALL unused Docker data
```

### Service-Specific Commands

**Database (PostgreSQL)**
```bash
# Connect to database
docker compose exec db psql -U postgres -d postgres

# Create backup
docker compose exec -T db pg_dump -U postgres -Fc -d postgres > backup.dump

# Restore backup
cat backup.dump | docker compose exec -T db pg_restore -U postgres -d postgres
```

**Storage Service**
```bash
# Check storage usage
docker compose exec storage du -sh /var/lib/storage

# List uploaded files
docker compose exec storage find /var/lib/storage -type f
```

**Kong API Gateway**
```bash
# Check Kong status
docker compose exec kong kong health

# Reload Kong configuration
docker compose restart kong
```

### Emergency Recovery

**Complete Reset (Preserves Data)**
```bash
cd /srv/supabase
docker compose down
docker compose up -d
```

**Complete Reset (Removes Everything)**
```bash
cd /srv/supabase
docker compose down -v
rm -rf volumes/*
# Then re-run supabase-install.sh
```

**Backup Before Major Changes**
```bash
# Backup database
docker compose exec -T db pg_dump -U postgres -Fc -d postgres > backup.dump

# Backup .env file
cp .env .env.backup

# Backup docker-compose files
cp docker-compose.yml docker-compose.yml.backup
cp docker-compose.override.yml docker-compose.override.yml.backup
```

## Files & Locations

- **Project Directory**: `/srv/supabase`
- **Environment File**: `/srv/supabase/.env`
- **Docker Compose**: `/srv/supabase/docker-compose.yml`
- **Override Config**: `/srv/supabase/docker-compose.override.yml`
- **Storage Mount**: `/mnt/unraid/supabase-storage/<APEX_DOMAIN>`
- **Backup Files**: `/srv/supabase/.env.bak.*`
- **Installation Logs**: `/tmp/supabase-install-*.log`

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
