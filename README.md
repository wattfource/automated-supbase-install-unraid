# Supabase Self-Host Installer for Unraid 7

**Official Supabase on Debian 13 VM with Unraid cache/array storage split**

- ⚡ VM + database on cache (fast SSD)
- 🛡️ User files on array (slow but parity-protected)
- 🔒 NPM for SSL, firewall options
- 🎯 Only for: Unraid 7, Debian 13, NPM on host

```
┌──────────────────────────────────────────┐
│ UNRAID 7 (single IP)                     │
│                                          │
│  [Cache/SSD]        [Array/HDD+Parity]   │
│   Debian VM ◄─NFS/SMB─► storage/         │
│   (host net)              [domain]/      │
│       │                                   │
│   [NPM Docker]                           │
│    localhost:8000/3000                   │
└──────────────────────────────────────────┘
```

---

## Quick Start

### 1. Prerequisites (Do First)

**On Unraid:**
- Create share: `/mnt/user/supabase-storage/`
- Enable NFS export or SMB with credentials
- NPM container running
- DNS: `api.yourdomain.com` → Unraid IP

**Create VM:**
- Debian 13 minimal, 2 vCPU, 4GB RAM, 20GB vdisk on cache
- Network: Host mode (shares Unraid IP)
- Install: SSH + standard utils only

### 2. Run Installer

**From inside the Debian VM:**

```bash
sudo -i
apt update && apt -y upgrade
cd /root
curl -fsSL -o supabase-install.sh \
  https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/supabase-install.sh
chmod +x supabase-install.sh
./supabase-install.sh
```

**One-liner:**
```bash
sudo -i bash <(curl -fsSL https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/supabase-install.sh)
```

**Have ready:**
- Domain names (apex, api subdomain, studio subdomain)
- Unraid IP/hostname
- NFS or SMB (if SMB: username/password)
- SMTP settings (optional, can skip)

### 3. After Install

**Configure NPM (on Unraid):**

Create two proxy hosts:
- `api.yourdomain.com` → `http://localhost:8000` (enable websockets, SSL)
- `studio.yourdomain.com` → `http://localhost:3000` (SSL + access restriction)

**Get your keys:**
```bash
cat /srv/supabase/.env | grep -E '(ANON_KEY|SERVICE_ROLE_KEY)'
```

**Access:**
- Studio: `https://studio.yourdomain.com`
- API: `https://api.yourdomain.com`

---

## Common Operations

**View logs:**
```bash
cd /srv/supabase
docker compose logs -f
```

**Restart services:**
```bash
docker compose restart
```

**Update Supabase:**
```bash
docker compose pull && docker compose up -d
```

**Backup database:**
```bash
cd /srv/supabase
docker compose exec -T db pg_dump -U postgres -Fc -d postgres > backup-$(date +%F).dump
```

**Restore database:**
```bash
docker compose exec -T db pg_restore -U postgres -d postgres -c < backup-file.dump
```

---

## Detailed Setup Instructions

<details>
<summary><b>1. Create Unraid Storage Share</b></summary>

In Unraid Web UI:
1. **Shares** → **Add Share**
2. Settings:
   - Name: `supabase-storage`
   - Use cache: `No` (force to array)
   - Export: `Yes` (NFS) or Security: `Private` (SMB)

From Unraid terminal:
```bash
mkdir -p /mnt/user/supabase-storage/yourdomain.com
chmod 755 /mnt/user/supabase-storage/yourdomain.com
```

Verify NFS (if using):
```bash
showmount -e localhost
```
</details>

<details>
<summary><b>2. Create Debian 13 VM</b></summary>

In Unraid VM Manager:
- **VMs** → **Add VM** → **Linux**
- Name: `debian-supabase`
- CPUs: `2+`, RAM: `4096 MB+`
- vDisk: `/mnt/cache/domains/debian-supabase/vdisk1.img`, 20GB+
- **Network: Host mode** (important!)
- Boot Debian 13 netinstall ISO

During Debian install:
- Minimal install, no desktop
- Software: SSH + standard utils only
- Partitioning: Use entire disk

After install:
```bash
apt update && apt upgrade -y
apt install -y sudo
ping -c 3 google.com  # verify connectivity
```
</details>

<details>
<summary><b>3. Configure NPM & DNS</b></summary>

**DNS (at your provider):**
```
api.yourdomain.com    → Unraid IP
studio.yourdomain.com → Unraid IP
```

**NPM Proxy Hosts:**
- API: `http://localhost:8000` (enable websockets, SSL)
- Studio: `http://localhost:3000` (SSL, add access control)
</details>

<details>
<summary><b>4. What the Installer Does</b></summary>

Interactive prompts for:
- Domain names (apex, api, studio)
- SMTP settings (optional)
- Analytics enable/disable
- Port pinning (security)
- Firewall rules (optional UFW)
- Unraid storage (NFS/SMB)

Automated actions:
- Install Docker if missing
- Generate secure secrets + JWT tokens
- Fetch official Supabase docker setup
- Mount Unraid storage at `/mnt/unraid/supabase-storage/[domain]`
- Start all containers
- Install location: `/srv/supabase`

Time: 5-15 minutes
</details>

<details>
<summary><b>5. Backup Strategy</b></summary>

**Database (daily):**
```bash
cd /srv/supabase
docker compose exec -T db pg_dump -U postgres -Fc > backup-$(date +%F).dump
```

**Environment file:**
```bash
cp /srv/supabase/.env ~/backup-env-$(date +%F).env
```

**Auto-backup script:**
```bash
cat > /root/backup-supabase.sh <<'EOF'
#!/bin/bash
cd /srv/supabase
docker compose exec -T db pg_dump -U postgres -Fc > backups/db-$(date +%F).dump
find backups/ -name "db-*.dump" -mtime +7 -delete
EOF
chmod +x /root/backup-supabase.sh
(crontab -l; echo "0 2 * * * /root/backup-supabase.sh") | crontab -
```

**User files:** Already on array with parity protection
</details>

<details>
<summary><b>6. Disaster Recovery</b></summary>

If VM/cache fails:
1. Create new Debian 13 VM
2. Run installer with same domains
3. Stop services: `docker compose down`
4. Restore `.env` from backup
5. Restore database: `docker compose up -d db && sleep 10 && docker compose exec -T db pg_restore -U postgres -d postgres -c < backup.dump`
6. Start all: `docker compose up -d`

User files survive on array (parity-protected)
</details>

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Can't access API/Studio | Check NPM forwards to localhost:8000/3000, verify `docker compose ps` |
| Storage mount fails | Verify NFS export or SMB credentials, check `mount -a` |
| Email not sending | Edit `/srv/supabase/.env` SMTP settings, restart `docker compose up -d auth` |
| Port conflicts | Check `ss -tlnp \| grep -E ':(8000\|3000)'` |
| Forgot keys | `cat /srv/supabase/.env \| grep KEY` |

---

## Architecture Details

**Storage split:**
- VM/containers/database → cache (fast SSD, no redundancy)
- User uploaded files → array (slow HDD, parity-protected)

**Performance:**
- API/DB queries: Fast (cache)
- File uploads/downloads: Moderate (array over NFS/SMB)
- Good for: Most apps, reasonable file sizes
- Not for: Video streaming, real-time processing

**Failure scenarios:**
- Cache fails: VM lost, user files safe, rebuild VM + restore DB
- Array disk fails: Unraid rebuilds via parity, zero downtime

**Locations:**
```
Unraid: /mnt/user/supabase-storage/[domain]/
VM:     /mnt/unraid/supabase-storage/[domain]/  (mount)
        /srv/supabase/                          (app files)
```

---

**Support:** [GitHub Issues](https://github.com/wattfource/automated-supbase-install-unraid/issues) | [Supabase Docs](https://supabase.com/docs/guides/self-hosting)