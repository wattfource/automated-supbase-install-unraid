# Supabase Self-Host Setup for Unraid

## WATTFOURCE Grid Architecture

An awesome retro/cyberpunk-styled interactive installer for deploying Supabase on Unraid infrastructure.

### Features

- 🎨 **WATTFOURCE-style ASCII art** with cyan/blue/magenta color scheme
- 📊 **Progress indicators** with animated bars showing deployment status
- 🔒 **Security-focused** with port pinning and firewall hardening options
- 📝 **Descriptive paragraphs** explaining each configuration option
- 🎯 **Interactive prompts** with clear consequences and recommendations
- 💾 **Unraid storage integration** via NFS or SMB
- 🐳 **Docker-based deployment** with automatic container orchestration

### Architecture

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

### Installation

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
   - `api.yourdomain.com` → `http://VM-IP:8000` (Enable WebSockets)
   - `studio.yourdomain.com` → `http://VM-IP:3000` (Add access restrictions)

### Visual Style

The installer features a stunning **TRON-inspired** WATTFOURCE interface with:

#### Color Scheme
- **Cyan** (`#00FFFF`) - Primary borders, grid lines, and headers
- **Blue** (`#0066FF`) - Section headers and important data  
- **Green** (`#00FF00`) - Success messages, completion, and light cycle animation
- **Yellow** (`#FFFF00`) - Warnings and important notices
- **Red** (`#FF0000`) - Errors and critical issues
- **Magenta** (`#FF00FF`) - Interactive prompts

#### ASCII Art Features
- **Animated Light Cycles**: Classic TRON-style light cycle races around the border on startup
- **Three Brand Names**: SUPABASE, UNRAID, and WATTFOURCE displayed in custom ASCII art
- **Smooth Animations**: Border-drawing animations with racing effects
- **Clean Alignment**: Perfectly aligned 88-character wide ASCII boxes

### Security Features

- **Port Pinning**: Sensitive services (HTTPS 8443, DB ports 5432/6543) pinned to localhost
- **Firewall Hardening**: UFW + DOCKER-USER rules restrict access to NPM host only
- **Minimal Exposure**: Only Kong:8000 (API) and Studio:3000 (Dashboard) exposed to LAN
- **SSL Termination**: Handled by Nginx Proxy Manager, not by Supabase containers

### Storage Strategy

- **VM & Containers**: Run on Unraid cache (SSD/NVMe) for speed
- **Supabase Storage**: Mounted from Unraid array (HDD) for redundancy
- **Mimics Supabase Cloud**: Fast compute, safe storage (like AWS S3)

### Post-Installation

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

### Files & Locations

- **Project Directory**: `/srv/supabase`
- **Environment File**: `/srv/supabase/.env`
- **Docker Compose**: `/srv/supabase/docker-compose.yml`
- **Override Config**: `/srv/supabase/docker-compose.override.yml`
- **Storage Mount**: `/mnt/unraid/supabase-storage/<APEX_DOMAIN>`
- **Backup Files**: `/srv/supabase/.env.bak.*`

### Requirements

- Debian 13 (or compatible Linux distribution)
- Root access
- Internet connectivity
- Unraid server with NFS or SMB enabled
- Domain names pointing to your Unraid server

### Support

This is a community-maintained installer. For Supabase issues, visit: https://supabase.com/docs

### License

MIT License - Feel free to modify and distribute

---

**Welcome to the WATTFOURCE Grid. Your Supabase instance awaits deployment.**
