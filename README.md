# Automated Supabase Self-Host Installer for Unraid

A comprehensive, interactive installer script that sets up **official Supabase** on a **Debian 13 VM** designed specifically for **Unraid 7** architectures with cache and array storage.

## 🎯 Who Is This For?

This installer is **specifically designed** for:
- **Unraid 7 users** with cache drives (SSD/NVMe) and redundant array (parity-protected HDDs)
- Users who want to run Supabase in a **Debian 13 minimal VM** on Unraid
- Setups where **Nginx Proxy Manager runs as a Docker container on the Unraid HOST**
- Users who want to separate compute (fast cache) from storage (safe array)

**This is NOT a generic installer.** It's an opinionated, architecture-specific setup optimized for Unraid environments.

---

## 🏗️ Architecture Overview

### The Complete Picture

```
┌─────────────────────────────────────────────────────────────┐
│ UNRAID 7 HOST (Single IP Address)                          │
│                                                             │
│  ┌────────────────┐           ┌───────────────────┐       │
│  │ CACHE (Fast)   │           │ ARRAY (Redundant) │       │
│  │ SSD/NVMe       │           │ HDD with parity   │       │
│  │                │           │                   │       │
│  │ • Debian 13 VM │           │ • Supabase        │       │
│  │   (containers) │◄─────NFS/SMB────► storage/     │       │
│  │   HOST NET MODE│           │   [domain]/       │       │
│  │   (shares IP)  │           │                   │       │
│  └────────────────┘           └───────────────────┘       │
│         │                                                   │
│  ┌──────▼─────────────────────────────┐                   │
│  │ Docker: Nginx Proxy Manager (NPM)  │                   │
│  │ • SSL termination                  │                   │
│  │ • Proxy: localhost:8000/3000       │                   │
│  └────────────────────────────────────┘                   │
└─────────────────────────────────────────────────────────────┘
         │                                    ▲
         │ HTTPS                              │ HTTP (internal)
         ▼                                    │
    Internet/LAN ──────────────────────► localhost:8000 (API)
                                         localhost:3000 (Studio)
```

### Why This Architecture?

**Mimics Supabase Cloud's approach:**
- **Supabase Cloud** uses compute instances + S3 storage
- **This setup** uses cache (compute) + array (storage)

**Performance vs. Redundancy Trade-offs:**
- **VM on cache:** Fast SSD/NVMe for containers, database, and processing
- **Storage on array:** Slower HDDs BUT protected by parity (1 or 2 disk failure tolerance)
- **Result:** Your uploaded files are safe even if a drive fails, while the app stays fast

**Storage Strategy Explained:**
- User uploaded files (images, documents, videos) → Unraid array
- Files can be large and don't need speed, but DO need redundancy
- If an array disk fails, you don't lose data (parity rebuilds)
- If cache fails, VM is replaceable; storage is preserved

### Storage Locations in Detail

**On Unraid HOST:**
```
/mnt/cache/              ← VM vdisk lives here (fast, no redundancy)
  └── vms/debian13/

/mnt/user/               ← Unraid user shares (cache + array)
  └── supabase-storage/  ← Storage share for Supabase
      └── example.com/   ← Per-domain storage folder
```

**Inside the VM:**
```
/srv/supabase/                          ← All Supabase files (on VM vdisk)
  ├── docker-compose.yml
  ├── .env                               ← Secrets and config
  └── docker volumes/                    ← Postgres, logs, etc.

/mnt/unraid/supabase-storage/           ← NFS/SMB mount point
  └── example.com/                       ← Mounted from Unraid array
      └── (user uploaded files)          ← These files on slow but safe array
```

**What Lives Where & Why:**

| Component | Location | Speed | Redundancy | Why? |
|-----------|----------|-------|------------|------|
| VM OS & containers | Cache (SSD) | Fast | None | Need speed, easily replaceable |
| PostgreSQL database | Cache (VM vdisk) | Fast | None* | Need speed, backup via pg_dump |
| Supabase config (.env) | Cache (VM vdisk) | Fast | None* | Small file, backup manually |
| User uploaded files | Array (HDD) | Slow | Yes (parity) | Large, need safety not speed |

*\*Backup via snapshots/dumps, not parity. See Backup Strategy below.*

### What Happens When...

**If a cache drive fails:**
- ❌ VM stops (vdisk is gone)
- ✅ User uploaded files are SAFE (on array)
- 🔄 Recovery: Create new VM, run installer again, restore database backup
- ⏱️ Downtime: 30-60 minutes

**If an array disk fails:**
- ✅ Unraid rebuilds from parity (automatic)
- ✅ VM keeps running (on cache)
- ✅ No data loss
- ⏱️ Downtime: None (rebuild happens in background)

**Performance Expectations:**
- **API requests:** Fast (served from VM on cache)
- **Database queries:** Fast (PostgreSQL on cache)
- **File uploads:** Moderate (writes to array over network)
- **File downloads:** Moderate to slow (reads from array over network)
- **Acceptable for:** Most self-hosted apps with reasonable file sizes
- **Not ideal for:** Video streaming, real-time file processing

---

## ⚠️ Important: This is an Interactive Installer

**This script will ask you questions during installation.** It's not a "set and forget" script. Have the information listed in the Prerequisites section ready before you start.

---

## 🎯 What This Script Actually Does

This is a **complete Supabase self-hosting setup**, not just a simple install. The script will:

1. **Install Dependencies** (if missing)
   - Docker Engine + Compose plugin
   - Required tools: `jq`, `openssl`, `git`, `curl`
   - NFS or SMB tools for network storage

2. **Interactive Configuration** (you'll be asked for):
   - Your domain names (apex domain, API subdomain, Studio subdomain)
   - SMTP email settings (optional during install)
   - Whether to enable Analytics (Logflare)
   - Port security settings (which ports to lock down)
   - Firewall configuration (optional UFW setup)
   - Unraid storage connection (NFS or SMB)

3. **Security Setup**
   - Generates secure passwords, JWT secrets, and encryption keys
   - Creates JWT tokens for API access (anon and service_role)
   - Optionally pins sensitive ports (HTTPS, database) to localhost only
   - Optionally configures UFW firewall to restrict access

4. **Network Configuration**
   - Exposes **only** Kong API (port 8000) and Studio (port 3000) to your LAN
   - Keeps database, authentication, and other services internal to Docker
   - Mounts Unraid storage for file uploads/storage

5. **Service Deployment**
   - Fetches official Supabase Docker setup
   - Creates custom configuration files
   - Starts all Supabase containers
   - Verifies services are running

---

## 📋 Prerequisites

### Unraid Host Requirements
- **Unraid 7** (required - this installer is only tested on Unraid 7)
- **Cache drive(s)** (SSD/NVMe recommended) for VM
- **Array with parity** (1 or 2 disk redundancy) for storage
- **Sufficient cache space** for VM (20GB+ recommended)
- **Array storage** for Supabase files (size depends on your needs)

### VM Requirements (Running on Unraid)
- **Debian 13 minimal install** (required - only confirmed working on Debian 13)
  - Create VM using Unraid's VM Manager
  - Install on cache (vdisk on cache)
  - Minimum 2 vCPU, 4GB RAM
  - 20GB+ storage for OS and containers
- **Root access** (`sudo -i`)
- **Network:** Host network mode (VM shares Unraid's network stack)

### Unraid Host Components (Already Running)
- **Nginx Proxy Manager (NPM)** as a Docker container on Unraid HOST
  - NOT in the VM - must be on the Unraid host
  - Used for SSL termination and reverse proxy
  - Must be able to reach VM IP
- **NFS or SMB** share configured on Unraid
  - Create share: `/mnt/user/supabase-storage/`
  - NFS: Enable NFS export for the share
  - SMB: Set username/password if using SMB

### Network Requirements
- **Domain name** with DNS pointed to your Unraid server IP
  - Subdomains for API and Studio
  - DNS managed externally (Cloudflare, etc.)
- **VM uses host networking** - shares Unraid's network stack and IP
- **NPM proxies to localhost** ports 8000 and 3000 (since VM shares host network)

### Before You Run the Installer
- ✅ Unraid server is running and accessible
- ✅ Cache and array are online
- ✅ Debian 13 minimal VM is created and running on cache
- ✅ VM configured with host networking (shares Unraid's network)
- ✅ VM has internet connectivity
- ✅ NPM is running on Unraid host
- ✅ Domain DNS points to Unraid IP
- ✅ Unraid share created for storage (NFS or SMB enabled)

### Information to Have Ready

Before running the script, gather this information:

1. **Domain Configuration**
   - Your apex domain (e.g., `example.com`)
   - Subdomain for API (e.g., `api.example.com`)
   - Subdomain for Studio admin panel (e.g., `studio.example.com`)

2. **Email/SMTP** (optional, can set later)
   - SMTP host (e.g., `smtp.gmail.com`)
   - SMTP port (usually `587`)
   - SMTP username
   - SMTP password

3. **Unraid Storage**
   - Unraid server IP or hostname (e.g., `192.168.1.75` or `unraid.lan`)
   - Whether to use NFS or SMB for storage
   - If SMB: username and password for the share

4. **Network Security** (optional)
   - NPM host IP address (if setting up firewall rules)
   - Admin IP range for SSH access (e.g., `192.168.1.0/24`)

---

## 🔧 Unraid Setup Guide (Do This First)

Before running the installer in your VM, set up these prerequisites on your Unraid host:

### Step 1: Create Unraid Storage Share

**Using Unraid Web UI:**

1. Go to **Shares** tab
2. Click **Add Share**
3. Configure:
   - **Share name:** `supabase-storage`
   - **Use cache:** `No` (force to array for redundancy)
   - **Export:** `Yes` (if using NFS)
   - **Security:** `Private` (if using SMB, set user/pass)
4. Click **Add Share**

**Verify NFS Export (if using NFS):**
```bash
# From Unraid terminal
showmount -e localhost
# Should show: /mnt/user/supabase-storage
```

**Create domain subdirectory:**
```bash
# From Unraid terminal
mkdir -p /mnt/user/supabase-storage/yourdomain.com
chmod 755 /mnt/user/supabase-storage/yourdomain.com
```

### Step 2: Create Debian 13 VM

**Using Unraid VM Manager:**

1. Go to **VMs** tab
2. Click **Add VM**
3. Select **Linux**
4. Configure VM:
   - **Name:** `debian-supabase`
   - **CPUs:** `2` (minimum, more if available)
   - **Initial Memory:** `4096 MB` (4GB minimum, more recommended)
   - **Machine:** `Q35-7.2`
   - **BIOS:** `OVMF`
   - **USB Controller:** None needed
   - **OS Install ISO:** Upload Debian 13 netinstall ISO
   - **Primary vDisk:**
     - **Location:** `Manual`
     - **Path:** `/mnt/cache/domains/debian-supabase/vdisk1.img`
     - **Size:** `20GB` or more
   - **Network:**
     - **Network Source:** `None` or `Host passthrough` 
     - **Network Model:** Leave empty or `virtio-net`
     - **IMPORTANT:** VM should use host network mode (shares Unraid's network)
5. Click **Create**

**Install Debian 13:**
1. Start the VM and connect via VNC
2. Install Debian with these choices:
   - **Install type:** Debian minimal (no desktop)
   - **Hostname:** `debian-supabase` (or any name)
   - **Partitioning:** Use entire disk (simple, one partition)
   - **Software selection:** 
     - ✅ SSH server
     - ✅ Standard system utilities
     - ❌ Uncheck everything else (no desktop, no web server)
3. After install, reboot

**Initial VM Setup:**
```bash
# Access the VM console via Unraid VNC or SSH to Unraid IP
# (Since VM uses host networking, SSH to Unraid IP might connect to VM)

# From VM console:

# Update system
apt update && apt upgrade -y

# Install sudo (minimal install doesn't have it)
apt install -y sudo

# Verify internet connectivity
ping -c 3 google.com

# (Optional) Create non-root user if you prefer
# adduser yourusername
# usermod -aG sudo yourusername
```

### Step 3: Verify NPM is Running

**Check NPM on Unraid:**

1. Go to **Docker** tab
2. Verify **Nginx Proxy Manager** container is running
3. Access NPM web UI (usually `http://unraid-ip:81`)
4. Make sure you can log in

**Note about Host Networking:**
Since the VM uses host networking, it shares Unraid's network stack. This means:
- VM doesn't have its own IP address
- Services in the VM are accessible on Unraid's IP
- NPM will proxy to `localhost:8000` and `localhost:3000`

### Step 4: DNS Configuration

**Set up DNS records** (at your DNS provider like Cloudflare):

```
Type  Name              Target              TTL
A     api.example.com   [Your-Unraid-IP]    Auto
A     studio.example.com [Your-Unraid-IP]   Auto
```

**Note:** DNS points to Unraid IP. Since the VM uses host networking (shares Unraid's IP), NPM proxies to localhost ports that the VM exposes.

---

## 🚀 Installation Methods

### Method 1: Multi-Step Install (Recommended for First-Time Users)

This method downloads the script first so you can review it before running:

```bash
# 1) Become root user
sudo -i

# 2) (Optional but recommended) Update your system first
apt update && apt -y upgrade

# 3) Download the installer script from GitHub
cd /root
curl -fsSL -o supabase-install.sh \
  https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/supabase-install.sh

# 4) Make the script executable
chmod +x supabase-install.sh

# 5) Run the installer (it will ask you questions)
./supabase-install.sh
```

**What this does in plain English:**
- `sudo -i` = Switch to root user (needed for system changes)
- `apt update && apt -y upgrade` = Update your system packages (optional but smart)
- `curl -fsSL -o` = Download the script from GitHub
- `chmod +x` = Make the script runnable
- `./supabase-install.sh` = Run the installer

---

### Method 2: One-Liner Install (For Advanced Users)

This runs the installer directly from GitHub without downloading it first:

```bash
sudo -i bash <(curl -fsSL https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/supabase-install.sh)
```

**What this does in plain English:**
- Downloads and runs the script in one command
- You become root and execute the script immediately
- **Warning:** You won't see the script contents before it runs

---

### Method 3: Using wget (If curl is not available)

Some minimal systems don't have `curl` installed by default:

```bash
# 1) Become root
sudo -i

# 2) Install wget if needed
apt update && apt -y install wget

# 3) Download the installer using wget
cd /root
wget -O supabase-install.sh https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/supabase-install.sh

# 4) Make it executable and run
chmod +x supabase-install.sh
./supabase-install.sh
```

**What this does in plain English:**
- Same as Method 1, but uses `wget` instead of `curl` to download

---

## 🎬 What Happens During Installation

The script will:

1. **Check for root access** - Exits if you're not root
2. **Ask about Docker** - Offers to install if missing
3. **Ask for your domains** - You'll type in your apex and subdomains
4. **Ask about email** - You can skip and configure later
5. **Ask about analytics** - Whether to enable Logflare (optional)
6. **Ask about port security** - Whether to lock ports to localhost
7. **Ask about firewall** - Whether to set up UFW rules
8. **Ask about storage** - NFS or SMB connection to Unraid
9. **Show you a summary** - Confirms your choices before proceeding
10. **Download Supabase** - Gets the official Docker setup
11. **Generate secrets** - Creates secure passwords and keys
12. **Configure everything** - Writes config files
13. **Mount storage** - Connects to your Unraid share
14. **Start services** - Launches all Docker containers
15. **Show next steps** - Tells you what to do in NPM

**Installation time:** 5-15 minutes depending on your internet speed and whether Docker needs to be installed.

---

## 📍 Where Everything Gets Installed

- **Main installation directory:** `/srv/supabase`
  - All Supabase files, Docker configs, and environment settings
  - The `.env` file with your secrets (automatically backed up)
  - Docker Compose files for running services

- **Storage mount point:** `/mnt/unraid/supabase-storage/[your-domain]`
  - This is where uploaded files are stored
  - Connects to your Unraid server's storage
  - Survives container restarts

- **Container data:** Managed by Docker volumes
  - Database data, logs, and internal files
  - Automatically created by Docker

---

## 🔐 Security Features

### Automatic Security Measures
- **Secure secret generation** - All passwords, JWT secrets, and encryption keys are randomly generated with cryptographically secure methods
- **Minimal port exposure** - Only ports 8000 (API) and 3000 (Studio) are accessible on your LAN
- **Database isolation** - PostgreSQL never exposed outside Docker network
- **Environment file protection** - `.env` file set to 600 permissions (owner read/write only)
- **Automatic backups** - `.env` backed up before any changes

### Optional Security (You'll Be Asked)
- **Port pinning** - Lock HTTPS (8443) and database ports (5432/6543) to localhost only
- **UFW firewall** - Restrict 8000/3000 to only your NPM server's IP address
- **SSH restrictions** - Limit SSH access to your admin subnet

### Important Security Notes
- ⚠️ **Change default Studio access** - Use NPM to add IP allowlist or basic auth
- ⚠️ **Don't expose ports to the internet** - Always use NPM for SSL termination
- ⚠️ **Keep your `.env` file secure** - Contains sensitive credentials
- ⚠️ **Use strong SMTP passwords** - If configuring email

---

## 📝 After Installation: Next Steps

The script will show you these steps at the end, but here's the detailed version:

### 1. Configure Nginx Proxy Manager (NPM) on Unraid

You need to create two Proxy Hosts in NPM:

**API Proxy Host:**
- **Domain:** `api.example.com` (use your actual API domain)
- **Forward to:** `http://localhost:8000` or `http://127.0.0.1:8000`
- **Enable:** Websockets Support (important!)
- **SSL:** Request Let's Encrypt certificate
- **Purpose:** This is the public API endpoint your apps will use
- **Note:** Use localhost because VM shares Unraid's network (host networking)

**Studio Proxy Host:**
- **Domain:** `studio.example.com` (use your actual Studio domain)
- **Forward to:** `http://localhost:3000` or `http://127.0.0.1:3000`
- **SSL:** Request Let's Encrypt certificate
- **Security:** Add Access List to restrict by IP, or use basic authentication
- **Purpose:** This is the admin dashboard (like phpMyAdmin but for Supabase)
- **Note:** Use localhost because VM shares Unraid's network (host networking)

### 2. Verify Storage Mount

Check that Unraid storage is properly connected:

```bash
# On your VM, check if the mount exists
df -h | grep supabase-storage

# Test access from inside the storage container
docker compose exec storage ls -l /var/lib/storage
```

**What this does:** Confirms your Unraid storage is accessible to the container.

### 3. Configure Email (If You Skipped It)

If you didn't set up SMTP during install:

```bash
# Edit the .env file
cd /srv/supabase
nano .env

# Find and update these lines:
# GOTRUE_SMTP_HOST=your.smtp.host
# GOTRUE_SMTP_PORT=587
# GOTRUE_SMTP_USER=your-email@domain.com
# GOTRUE_SMTP_PASS=your-password

# Restart the auth service to apply changes
docker compose up -d auth
```

**What this does:** Enables Supabase to send verification emails, password resets, etc.

### 4. Access Your Supabase Instance

- **Studio (Admin Panel):** `https://studio.example.com`
  - Log in using the credentials created during setup
  - This is where you manage databases, users, storage, etc.

- **API Endpoint:** `https://api.example.com`
  - Use this in your applications
  - You'll need your ANON_KEY and SERVICE_ROLE_KEY from `/srv/supabase/.env`

---

## 🛠️ Common Operations

### View Running Services
```bash
cd /srv/supabase
docker compose ps
```

### View Logs
```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f kong
docker compose logs -f auth
docker compose logs -f storage
```

### Restart Services
```bash
cd /srv/supabase
docker compose restart

# Or restart specific service
docker compose restart kong
```

### Update Supabase
```bash
cd /srv/supabase
docker compose pull    # Download latest images
docker compose up -d   # Restart with new versions
```

### Backup Strategy (Unraid-Specific)

**What needs backing up:**

1. **PostgreSQL Database** (on cache - not parity protected)
   ```bash
   cd /srv/supabase
   mkdir -p backups
   docker compose exec -T db pg_dump -U postgres -Fc -d postgres > "backups/$(date +%F_%H-%M).dump"
   ```

2. **Environment file** (contains all secrets)
   ```bash
   cp /srv/supabase/.env ~/supabase-env-backup-$(date +%F).env
   ```

3. **User uploaded files** (already on array with parity - but consider offsite backup)
   ```bash
   # From Unraid host, backup to external drive or cloud
   rsync -av /mnt/user/supabase-storage/ /mnt/backup/supabase-storage-backup/
   ```

**Recommended Backup Schedule:**
- **Daily:** Database dump (automated via cron in VM)
- **Weekly:** Copy database dumps to Unraid array
- **Monthly:** Offsite backup of array storage

**Automated Daily Database Backup:**
```bash
# In the VM, create a backup script
cat > /root/backup-supabase.sh <<'EOF'
#!/bin/bash
cd /srv/supabase
mkdir -p backups
# Keep last 7 days
docker compose exec -T db pg_dump -U postgres -Fc -d postgres > "backups/supabase-$(date +%F).dump"
find backups/ -name "supabase-*.dump" -mtime +7 -delete
EOF

chmod +x /root/backup-supabase.sh

# Add to crontab (runs daily at 2 AM)
(crontab -l 2>/dev/null; echo "0 2 * * * /root/backup-supabase.sh") | crontab -
```

**Copy Backups to Unraid Array:**
```bash
# From VM, copy to Unraid array (safe storage)
rsync -av /srv/supabase/backups/ /mnt/unraid/supabase-storage/$(cat /srv/supabase/.env | grep APEX | cut -d= -f2)/backups/
```

### Restore Database
```bash
cd /srv/supabase
docker compose exec -T db pg_restore -U postgres -d postgres -c < backups/your-backup.dump
```

### Complete Disaster Recovery

**If you lose the entire VM (cache failure):**

1. **Create new Debian 13 VM** on Unraid
2. **Run the installer** again with same domain settings
3. **Stop services:**
   ```bash
   cd /srv/supabase
   docker compose down
   ```
4. **Restore .env file** (from your backup)
5. **Restore database:**
   ```bash
   docker compose up -d db
   sleep 10
   docker compose exec -T db pg_restore -U postgres -d postgres -c < backups/your-backup.dump
   ```
6. **Start all services:**
   ```bash
   docker compose up -d
   ```
7. **Verify storage mount** is connected to Unraid array (files preserved)

### Stop Everything
```bash
cd /srv/supabase
docker compose down
```

### Completely Remove Supabase (Nuclear Option)
```bash
cd /srv/supabase
docker compose down -v  # Remove containers and volumes
cd ..
rm -rf /srv/supabase    # Delete all files
umount /mnt/unraid/supabase-storage/[your-domain]  # Unmount storage
```

---

## 🐛 Troubleshooting

### Script Fails: "Docker not found"
**Problem:** Docker isn't installed and auto-install was declined.  
**Solution:** Re-run the script and answer "y" when asked to install Docker.

### Can't Access Studio or API
**Problem:** NPM not configured or services not running.  
**Solution:** 
1. Check NPM proxy hosts are created correctly (should forward to localhost:8000 and localhost:3000)
2. From Unraid terminal, test if services are responding: `curl http://localhost:8000` (should get a response)
3. Check if containers are running in VM: `docker compose ps`
4. Check VM is running in Unraid VM Manager

### Storage Mount Fails
**Problem:** NFS/SMB connection issues.  
**Solution:**
1. Check Unraid share exists and is accessible
2. For NFS: `showmount -e [unraid-ip]` (should list exports)
3. For SMB: Test credentials are correct
4. Check `/etc/fstab` has correct entry
5. Manually test: `mount -a`

### Email Not Sending
**Problem:** SMTP not configured or credentials wrong.  
**Solution:**
1. Check `.env` file has correct SMTP settings
2. Test SMTP credentials using a mail client
3. Check firewall allows outbound port 587/465
4. Restart auth service: `docker compose restart auth`

### Services Won't Start
**Problem:** Port conflicts or resource issues.  
**Solution:**
1. Check what's using ports: `ss -tlnp | grep -E ':(8000|3000|5432)'`
2. Check Docker status: `systemctl status docker`
3. Check resources: `free -h` and `df -h`
4. View specific service logs: `docker compose logs [service-name]`

### Forgot Passwords/Keys
**Problem:** Need to find generated secrets.  
**Solution:**
```bash
cd /srv/supabase
cat .env | grep -E '(ANON_KEY|SERVICE_ROLE_KEY|POSTGRES_PASSWORD)'
```

---

## 🤝 Support

- **GitHub Issues:** [Report problems or request features](https://github.com/wattfource/automated-supbase-install-unraid/issues)
- **Supabase Docs:** [Official self-hosting documentation](https://supabase.com/docs/guides/self-hosting)

---

## 📄 License

This installer script is provided as-is for setting up Supabase self-hosted instances. Supabase itself is licensed under the Apache License 2.0.