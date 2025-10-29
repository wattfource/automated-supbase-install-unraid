# Port and Storage Configuration (Without docker-compose.override.yml)

The Supabase installer no longer creates `docker-compose.override.yml`. This document explains how to configure ports and storage directly.

## Configuring Ports

All port configuration is done via environment variables in `.env`. No override file needed.

### Port Environment Variables

These are set automatically during installation:

```bash
# Kong API Gateway ports
KONG_HTTP_PORT=8000
KONG_HTTPS_PORT=8443

# Database pooler (Supavisor)
POOLER_PROXY_PORT_TRANSACTION=6543

# Studio Dashboard
# (Port 3000 is hardcoded in the container, cannot be changed via env var)
```

### Changing Port Configuration

If you need to change port assignments after installation:

**1. Edit `.env` file:**
```bash
sudo nano /srv/supabase/.env
```

**2. Modify the port variables:**
```bash
# Change Kong HTTP port from 8000 to 8001
KONG_HTTP_PORT=8001
```

**3. Restart containers:**
```bash
cd /srv/supabase
docker compose down
docker compose up -d
```

### Accessing Services

After setting your ports, services are accessed via:

```bash
# Kong API Gateway (changeable)
http://192.168.1.51:${KONG_HTTP_PORT}

# Kong HTTPS (changeable)
https://192.168.1.51:${KONG_HTTPS_PORT}

# Supavisor Database Pooler (port 6543 - hardcoded in container)
postgresql://user:password@192.168.1.51:6543/postgres

# Studio Dashboard (port 3000 - hardcoded in container)
http://192.168.1.51:3000
```

## Configuring Storage

Storage is configured via the `.env` file and Docker volume mounts in `docker-compose.yml`.

### Storage Environment Variables

```bash
# Enable/disable file storage
STORAGE_BACKEND=file        # or "stub" to disable

# File size limit (default: 524288000 bytes = 500MB)
FILE_SIZE_LIMIT=524288000
```

### Storage Mount Point

Storage data is mounted at the container path:
```
/var/lib/storage    (inside container)
```

### Configuring Storage Path (For Deployed Instances)

If you have an existing deployment and need to add/change storage:

**Option 1: Edit docker-compose.yml directly**

Locate the `storage` service and add/modify the volume:

```yaml
storage:
  volumes:
    - /mnt/unraid/supabase-storage/yourdomain.com:/var/lib/storage
```

Then restart:
```bash
cd /srv/supabase
docker compose restart storage
```

**Option 2: Use environment variables**

The storage path can be passed via environment variable. Create a custom startup script or modify your deployment process to inject the volume.

### Storage Examples

**Local file storage:**
```yaml
volumes:
  - /srv/supabase/storage:/var/lib/storage
```

**Unraid NFS mount:**
```yaml
volumes:
  - /mnt/unraid/supabase-storage/example.com:/var/lib/storage
```

**Unraid SMB mount:**
```yaml
volumes:
  - /mnt/smb/supabase-storage/example.com:/var/lib/storage
```

## Deploying Without docker-compose.override.yml

The official `docker-compose.yml` from Supabase includes sensible defaults for port bindings.

### Default Ports in docker-compose.yml

The base Supabase docker-compose.yml typically exposes:
```
studio: 3000
kong: 8000, 8443
supavisor: 6543
db: 5432 (internal only)
```

### If You Need Custom Ports

You have two options:

**Option A: Modify docker-compose.yml directly**

```bash
cd /srv/supabase
nano docker-compose.yml
```

Find the service and change its port mapping:
```yaml
kong:
  ports:
    - "9000:8000"      # Map container port 8000 to host port 9000
    - "9443:8443"      # Map container port 8443 to host port 9443
```

Then restart:
```bash
docker compose down
docker compose up -d
```

**Option B: Use a reverse proxy (Recommended)**

Use Nginx Proxy Manager on Unraid host:
- `api.yourdomain.com` → `http://192.168.1.51:8000`
- `app.yourdomain.com` → your frontend app
- (Optional) `admin.yourdomain.com` → `http://192.168.1.51:3000`

This is cleaner and doesn't modify the base Supabase configuration.

## For Deployed Instances With docker-compose.override.yml

If you already have a deployment using `docker-compose.override.yml`, here's how to migrate away from it:

### Step 1: Backup Current Config

```bash
cd /srv/supabase
cp docker-compose.override.yml docker-compose.override.yml.backup
```

### Step 2: Extract Configuration

Look at what your override file contains and note:
- Any custom port mappings
- Storage volume mounts
- Service port configurations

### Step 3: Apply Configuration Directly

**For ports:** Modify `.env` or edit `docker-compose.yml` directly

**For storage:** Edit the `storage` service in `docker-compose.yml` and add volume mounts

Example:
```yaml
storage:
  environment:
    - FILE_SIZE_LIMIT=524288000
  volumes:
    - /mnt/unraid/supabase-storage/yourdomain.com:/var/lib/storage
```

### Step 4: Verify Configuration

```bash
cd /srv/supabase
docker compose config    # Shows merged configuration
```

### Step 5: Redeploy

```bash
# Remove old containers
docker compose down

# Restart with new configuration
docker compose up -d

# Verify services are running
docker compose ps
```

### Step 6: Remove Override File (Optional)

Once everything is working:

```bash
cd /srv/supabase
rm docker-compose.override.yml
```

Note: If `docker-compose.override.yml` still exists, Docker Compose will still use it. Removing it ensures a clean state.

## Troubleshooting

### Port Already in Use

```bash
# Find what's using the port
sudo ss -tulpn | grep :8000

# Or check Docker specifically
docker ps --format "table {{.Names}}\t{{.Ports}}"
```

### Storage Not Mounting

```bash
# Check volume mounts
docker inspect supabase-storage | grep -A 5 Mounts

# Check mount point exists
ls -la /mnt/unraid/supabase-storage/

# Check permissions
sudo chown -R root:root /mnt/unraid/supabase-storage
```

### Services Not Starting After Config Change

```bash
# Check logs
docker compose logs storage
docker compose logs kong

# Validate docker-compose.yml syntax
docker compose config
```

## Best Practices

1. **Always backup** `.env` and `docker-compose.yml` before making changes
2. **Use `.env` for secrets** - never hardcode credentials in docker-compose.yml
3. **Use environment variables** - they're overridden by `.env`
4. **Use reverse proxy** - cleaner than modifying port mappings
5. **Test changes** - restart containers and verify logs before going to production

