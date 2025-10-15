# Supabase Self-Host Installer for Unraid

Automated installer for deploying Supabase on Unraid infrastructure with a Debian 13 VM.

## What This Does

Installs and configures the official Supabase self-hosted stack with:
- Automated dependency installation (Docker, tools)
- Interactive configuration with sensible defaults
- Storage integration with Unraid array (NFS or SMB)
- Optional UFW firewall hardening
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

1. **Prepare Your Unraid Server**
   - Create a Debian 13 VM on Unraid cache
   - Create a `supabase-storage` share on your Unraid array
   - Install Nginx Proxy Manager on Unraid host

2. **Run the Installer (One-Liner)**
   ```bash
   sudo bash -c 'rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.gpg 2>/dev/null; apt update && apt -y upgrade && apt install -y wget curl gpg && cd /tmp && wget --no-cache -O supabase-install.sh https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/supabase-install.sh && chmod +x supabase-install.sh && ./supabase-install.sh'
   ```
   
   **What this does:**
   - ✅ Cleans up any broken Docker repository configurations first
   - ✅ Runs everything as root
   - ✅ Updates and upgrades system packages
   - ✅ Installs wget, curl, and gpg (required for Docker installation)
   - ✅ Downloads latest script (overwrites existing)
   - ✅ Makes executable and runs immediately
   
   Or download and run manually:
   ```bash
   sudo -i
   wget https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/supabase-install.sh
   chmod +x supabase-install.sh
   ./supabase-install.sh
   ```

3. **Follow the Interactive Prompts**
   The script will guide you through:
   - Docker installation (if needed)
   - Domain configuration (API & Studio)
   - SMTP email setup (optional)
   - Port configuration
   - Security options (port pinning & firewall)
   - Storage mount (NFS or SMB)
   
   **Troubleshooting: If prompts don't appear**
   ```bash
   # Skip the intro animation for faster/more reliable startup:
   SKIP_ANIMATION=1 ./supabase-install.sh
   ```
   
   **Troubleshooting: If you get Docker repository errors after a failed install**
   ```bash
   # Manual cleanup (the script now does this automatically):
   sudo rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.gpg
   sudo apt update
   # Then run the installer again
   ```

4. **Configure Nginx Proxy Manager**
   After installation, create two proxy hosts:
   - `api.yourdomain.com` → `http://localhost:8000` (Enable WebSockets)
   - `studio.yourdomain.com` → `http://localhost:3000` (Add access restrictions)

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
