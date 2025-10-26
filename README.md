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

## Database Backup & Restore

### Creating Backups

Your Supabase database can be backed up in multiple formats:

**PostgreSQL Custom Format (Recommended)**
```bash
cd /srv/supabase
mkdir -p backups
docker compose exec -T db pg_dump -U postgres -Fc -d postgres > "backups/backup-$(date +%F).dump"
```
✅ Best compression, fastest restore, includes metadata

**Plain SQL Format**
```bash
docker compose exec -T db pg_dump -U postgres -d postgres > "backups/backup-$(date +%F).sql"
```
✅ Human-readable, can be edited, universal compatibility

**Compressed SQL**
```bash
docker compose exec -T db pg_dump -U postgres -d postgres | gzip > "backups/backup-$(date +%F).sql.gz"
```
✅ Smallest file size, good for transfers

**Automated Backups (Cron)**
```bash
# Create backup script
sudo tee /srv/supabase/scripts/backup-database.sh > /dev/null << 'EOF'
#!/bin/bash
BACKUP_DIR="/srv/supabase/backups"
mkdir -p "$BACKUP_DIR"
cd /srv/supabase
docker compose exec -T db pg_dump -U postgres -Fc -d postgres > "$BACKUP_DIR/backup-$(date +%F-%H%M).dump"

# Keep only last 7 days of backups
find "$BACKUP_DIR" -name "backup-*.dump" -mtime +7 -delete
EOF

sudo chmod +x /srv/supabase/scripts/backup-database.sh

# Add to cron (daily at 2 AM)
(crontab -l 2>/dev/null; echo "0 2 * * * /srv/supabase/scripts/backup-database.sh") | crontab -
```

### Restoring Backups

**Using the Restore Script (Recommended)**
```bash
# Download the restore utility (if not already installed)
sudo bash -c 'cd /tmp && wget --no-cache -O restore-database.sh https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/restore-database.sh && chmod +x restore-database.sh && mv restore-database.sh /srv/supabase/scripts/'

# Restore from any backup format
sudo bash /srv/supabase/scripts/restore-database.sh /tmp/your-backup.dump
```

The restore script will:
- ✅ Automatically detect backup format
- ✅ Create a safety backup before restoring
- ✅ Verify database health after restore
- ✅ Restart dependent services
- ✅ Provide rollback instructions if needed

**Manual Restore (Advanced)**

*PostgreSQL Custom Format:*
```bash
cd /srv/supabase
cat backups/backup.dump | docker compose exec -T db pg_restore -U postgres -d postgres --clean --if-exists
```

*Plain SQL:*
```bash
cat backups/backup.sql | docker compose exec -T db psql -U postgres -d postgres
```

*Compressed SQL:*
```bash
zcat backups/backup.sql.gz | docker compose exec -T db psql -U postgres -d postgres
```

### Migrating from Supabase Cloud or Another Instance

**Method 1: Direct Backup from Cloud (Recommended)**

This method downloads directly from Supabase Cloud to your self-hosted instance over a secure SSL connection.

💡 **Tip:** If time has elapsed since your Supabase installation, [update the utilities](#updatereinstall-backup--restore-utilities) first to get the latest bug fixes and features.

```bash
# Download the backup-from-cloud script
sudo bash -c 'cd /tmp && wget --no-cache -O backup-from-cloud.sh https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/backup-from-cloud.sh && chmod +x backup-from-cloud.sh && mv backup-from-cloud.sh /srv/supabase/scripts/'

# Run the backup script (it will prompt for credentials)
sudo bash /srv/supabase/scripts/backup-from-cloud.sh

# Or run with auto-restore (backup and restore in one step)
sudo bash /srv/supabase/scripts/backup-from-cloud.sh --auto-restore
```

**Prerequisites:**
⚠️ **IPv4 Direct Connection Add-on is REQUIRED** (paid add-on in Supabase Cloud)

To enable:
1. Go to your Supabase Cloud project
2. Settings → Add-ons → IPv4 Address
3. Enable the IPv4 add-on
4. Wait for provisioning (few minutes)

**What you'll need from Supabase Cloud (after enabling IPv4):**
1. Go to Settings → Database → Connection string
2. Select **"Direct connection"** (port 5432, NOT pooled connection)
3. Verify **"IPv4 compatible"** is shown
4. Copy these values:
   - **Host**: `db.<project-ref>.supabase.co`
   - **Port**: `5432`
   - **Database**: `postgres` (usually)
   - **User**: `postgres`
   - **Password**: (reset if you don't know it)

**The script will:**
- ✅ Install PostgreSQL client tools if needed
- ✅ Test connection to Supabase Cloud (SSL)
- ✅ Show database size and statistics
- ✅ Download complete backup to `/srv/supabase/backups/`
- ✅ Optionally restore to local instance immediately
- ✅ Save credentials for future backups (optional)

**Method 2: Manual Export and Transfer**

From Supabase Cloud (via dashboard):
1. Go to Settings → Database → Database Backups
2. Click "Download" on the latest backup
3. Transfer to your VM

```bash
# Transfer backup to VM
scp supabase-backup.sql user@vm-ip:/tmp/

# Restore
sudo bash /srv/supabase/scripts/restore-database.sh /tmp/supabase-backup.sql
```

From another self-hosted instance:
```bash
# On source server
cd /srv/supabase
docker compose exec -T db pg_dump -U postgres -Fc -d postgres > migration-backup.dump

# Transfer to target
scp migration-backup.dump user@target-vm:/tmp/

# On target server
sudo bash /srv/supabase/scripts/restore-database.sh /tmp/migration-backup.dump
```

**Verify Migration**
```bash
# Check database
cd /srv/supabase
docker compose exec -T db psql -U postgres -d postgres -c "SELECT schemaname, COUNT(*) FROM pg_tables GROUP BY schemaname;"

# Check services
docker compose ps

# Test API
curl http://localhost:8000/rest/v1/
```

### Backup Best Practices

1. **Backup Frequency**
   - Production: Daily automated backups
   - Development: Before major changes
   - Pre-migration: Immediately before restore operations

2. **Backup Storage**
   - Keep backups on Unraid array (parity-protected)
   - Copy critical backups off-site (cloud storage, external drive)
   - Test restores periodically

3. **Backup Retention**
   - Daily backups: Keep 7 days
   - Weekly backups: Keep 4 weeks
   - Monthly backups: Keep 12 months

4. **What Gets Backed Up**
   - ✅ All database schemas and tables
   - ✅ User data and authentication
   - ✅ Row-level security policies
   - ✅ Database functions and triggers
   - ✅ Extensions and configurations
   - ❌ Storage files (backed up separately via Unraid share)
   - ❌ Environment variables (backup `.env` file separately)

5. **Storage Files Backup**
   ```bash
   # Your storage files are already on Unraid array (parity-protected)
   # Additional backup options:
   
   # Option A: Rsync to another location
   rsync -av /mnt/unraid/supabase-storage/ /mnt/backups/supabase-storage/
   
   # Option B: Tar archive
   tar -czf storage-backup-$(date +%F).tar.gz /mnt/unraid/supabase-storage/
   ```

### Troubleshooting Restores

**Issue: "Database already exists" errors**
```bash
# The restore script uses --clean to handle this automatically
# If manually restoring, add --clean flag:
cat backup.dump | docker compose exec -T db pg_restore -U postgres -d postgres --clean --if-exists
```

**Issue: Permission denied errors**
```bash
# Use --no-owner and --no-acl flags:
cat backup.dump | docker compose exec -T db pg_restore -U postgres -d postgres --clean --no-owner --no-acl
```

**Issue: Restore takes too long**
```bash
# For large databases, monitor progress:
docker compose logs -f db

# Check current database size:
docker compose exec -T db psql -U postgres -d postgres -c "SELECT pg_size_pretty(pg_database_size('postgres'));"
```

**Issue: Services not connecting after restore**
```bash
# Restart all services:
cd /srv/supabase
docker compose restart

# Or restart specific services:
docker compose restart auth rest storage
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

There are two methods to update your Supabase installation: **automated** (recommended) or **manual**.

#### Method 1: Automated Update Script (Recommended)

The update script handles everything safely:

**Download and run the updater:**
```bash
sudo bash -c 'cd /tmp && wget --no-cache -O update-supabase.sh https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/update-supabase.sh && chmod +x update-supabase.sh && ./update-supabase.sh'
```

**What the update script does:**
- ✅ Creates automatic backups (database, config files)
- ✅ Updates system packages (Docker, tools)
- ✅ Checks for new Supabase container images
- ✅ Applies updates with zero downtime
- ✅ Verifies all services are healthy
- ✅ Cleans up old images and backups
- ✅ Provides rollback instructions if needed

**Update frequency recommendations:**
- **Monthly**: Check for Supabase updates (new features, security patches)
- **Weekly**: System package updates (security updates)
- **As needed**: When Supabase releases critical fixes

#### Method 2: Manual Updates

If you prefer manual control:

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

**Update System Packages**
```bash
sudo apt update && sudo apt upgrade -y
```

#### Update Best Practices

1. **Before Updating:**
   ```bash
   # Create database backup
   cd /srv/supabase
   mkdir -p backups
   docker compose exec -T db pg_dump -U postgres -Fc -d postgres > "backups/db-$(date +%F).dump"
   
   # Backup config files
   cp .env backups/.env.backup
   cp docker-compose.override.yml backups/docker-compose.override.yml.backup
   ```

2. **During Updates:**
   - Updates typically take 2-5 minutes
   - Services restart automatically
   - Active connections may be briefly interrupted
   - Database data is always preserved

3. **After Updating:**
   ```bash
   # Verify all containers are healthy
   docker compose ps
   
   # Check for errors
   docker compose logs --tail=50
   
   # Test access to Studio and API
   curl http://YOUR-VM-IP:3000
   curl http://YOUR-VM-IP:8000
   ```

4. **Rollback if Needed:**
   ```bash
   cd /srv/supabase
   
   # Stop current containers
   docker compose down
   
   # Restore config
   cp backups/.env.backup .env
   
   # Restore database (if needed)
   cat backups/db-YYYY-MM-DD.dump | docker compose exec -T db pg_restore -U postgres -d postgres --clean
   
   # Start services
   docker compose up -d
   ```

#### Update Troubleshooting

**Container won't start after update:**
```bash
# Check specific container logs
docker compose logs <container-name>

# Force recreate all containers
docker compose up -d --force-recreate

# If database is corrupted, restore from backup
cat backups/db-latest.dump | docker compose exec -T db pg_restore -U postgres -d postgres --clean
```

**New version breaks compatibility:**
```bash
# Pin to specific working version in docker-compose.yml
# Example: supabase/studio:20241020-abc123 instead of :latest
nano docker-compose.yml

# Then redeploy
docker compose down
docker compose up -d
```

**Out of disk space during update:**
```bash
# Remove old unused images
docker image prune -a

# Check Docker disk usage
docker system df

# Clean up old backups
cd /srv/supabase/backups
ls -lt | tail -n +6 | awk '{print $NF}' | xargs rm -f
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
- **Helper Scripts**: `/srv/supabase/scripts/` (auto-installed during setup)
  - `diagnostic.sh` - System diagnostics
  - `update.sh` - Update automation
  - `backup-from-cloud.sh` - Cloud backup utility
  - `restore-database.sh` - Database restore utility
- **Storage Mount**: `/mnt/unraid/supabase-storage/<APEX_DOMAIN>`
- **Backup Directory**: `/srv/supabase/backups/`
- **Installation Logs**: `/tmp/supabase-install-*.log`

## Helper Scripts (Auto-Installed)

The installer automatically downloads and creates helper scripts for easy troubleshooting and maintenance. All scripts are placed in `/srv/supabase/scripts/` during installation:

### Diagnostic Script
**Location**: `/srv/supabase/scripts/diagnostic.sh`

Generates a comprehensive system report including:
- Container status and health
- Port bindings
- Encryption key formats
- Service logs
- Database connectivity
- Resource usage

**Usage:**
```bash
sudo bash /srv/supabase/scripts/diagnostic.sh
```

### Update Script
**Location**: `/srv/supabase/scripts/update.sh`

Simplified update process with automatic backups:
- Creates config and database backups
- Checks for new Docker images
- Applies updates safely
- Verifies service health
- Cleans up old resources

**Usage:**
```bash
sudo bash /srv/supabase/scripts/update.sh
```

### Database Backup from Cloud Script
**Location**: `/srv/supabase/scripts/backup-from-cloud.sh` *(auto-installed)*

Downloads database directly from Supabase Cloud to your self-hosted instance:
- Direct network backup over SSL connection
- No manual download/upload needed
- PostgreSQL client tools auto-installation
- Credential saving for repeated backups
- Optional auto-restore to local instance
- Database statistics and size reporting

**Usage:**
```bash
# Backup from Supabase Cloud (prompts for credentials)
sudo bash /srv/supabase/scripts/backup-from-cloud.sh

# Or backup and restore in one step
sudo bash /srv/supabase/scripts/backup-from-cloud.sh --auto-restore
```

**Requirements:**
- ⚠️ **IPv4 Direct Connection Add-on enabled** in Supabase Cloud (paid add-on)
- Supabase Cloud connection details (Host, Port, Database, User, Password)
- Found in: Project Settings → Database → Connection string (Direct connection)

### Database Restore Script
**Location**: `/srv/supabase/scripts/restore-database.sh` *(auto-installed)*

Restores database backups to your self-hosted Supabase instance:
- Supports multiple backup formats (PostgreSQL custom, SQL, compressed SQL)
- Automatic safety backup before restore
- Database health verification
- Service restart after restore
- Rollback support if needed

**Usage:**
```bash
# Restore any backup (auto-detects format)
sudo bash /srv/supabase/scripts/restore-database.sh /tmp/your-backup.dump
```

**Supported backup formats:**
- PostgreSQL custom format (`.dump`, `.backup`) - created with `pg_dump -Fc`
- Plain SQL files (`.sql`)
- Compressed SQL (`.sql.gz`)

**Complete Migration Workflow:**
```bash
# Single-command migration from Supabase Cloud
sudo bash /srv/supabase/scripts/backup-from-cloud.sh --auto-restore

# Or step-by-step:
# 1. Backup from cloud
sudo bash /srv/supabase/scripts/backup-from-cloud.sh

# 2. Restore to local (uses the downloaded backup)
sudo bash /srv/supabase/scripts/restore-database.sh /srv/supabase/backups/cloud-backup-*.dump
```

These scripts are automatically downloaded during Supabase installation.

### Update/Reinstall Backup & Restore Utilities

**When to use this:** If time has elapsed since your initial Supabase installation, the scripts may have been updated in the repository with bug fixes or new features. Use this one-liner to download and overwrite with the latest versions:

**One-liner to download/overwrite both utilities:**
```bash
sudo bash -c 'cd /srv/supabase/scripts && curl -fsSL https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/backup-from-cloud.sh -o backup-from-cloud.sh && curl -fsSL https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/restore-database.sh -o restore-database.sh && chmod +x backup-from-cloud.sh restore-database.sh && echo "✓ Backup and restore utilities updated"'
```

This will:
- Download the latest `backup-from-cloud.sh`
- Download the latest `restore-database.sh`
- Overwrite existing files
- Set proper permissions
- Confirm success

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
