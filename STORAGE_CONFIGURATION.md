# Storage Configuration - Direct Integration

The Supabase installer directly configures storage in `docker-compose.yml`. No override files are used.

## How Storage is Configured

### During Installation

1. You're asked if you want storage enabled:
   ```
   Enable Storage (file uploads)? [Y/n]: y
   ```

2. You choose the protocol (NFS or SMB):
   ```
   Storage protocol (nfs|smb): nfs
   ```

3. You provide Unraid details:
   - **Unraid Host**: `192.168.1.70`
   - **NFS Export Path**: `/mnt/user/supabase-storage/yourdomain.com`
   - **VM Mount Point**: `/mnt/unraid/supabase-storage/yourdomain.com`

4. The installer:
   - Mounts the Unraid share on the VM at the mount point
   - Updates `/etc/fstab` for persistent mounting
   - Directly modifies `docker-compose.yml` to mount this path into the storage container

### Result in docker-compose.yml

The storage service is configured like this:

```yaml
storage:
  volumes:
    - /mnt/unraid/supabase-storage/yourdomain.com:/var/lib/storage
```

**No override file is created.** The storage path is directly in `docker-compose.yml`.

## For Existing Deployments

If you already have a Supabase instance and need to add storage:

### Step 1: Create Mount Point on VM

```bash
# For NFS
sudo mkdir -p /mnt/unraid/supabase-storage/yourdomain.com

# For SMB  
sudo mkdir -p /mnt/smb/supabase-storage/yourdomain.com
```

### Step 2: Mount Unraid Share

**For NFS:**

```bash
# Add to /etc/fstab
sudo bash -c 'echo "192.168.1.70:/mnt/user/supabase-storage/yourdomain.com  /mnt/unraid/supabase-storage/yourdomain.com  nfs  defaults  0  0" >> /etc/fstab'

# Mount
sudo mount -a

# Verify
df -h | grep supabase-storage
```

**For SMB:**

```bash
# Create credentials file
sudo bash -c 'cat > /root/.smb-yourdomain.com.cred << CRED
username=your_smb_username
password=your_smb_password
CRED'

sudo chmod 600 /root/.smb-yourdomain.com.cred

# Add to /etc/fstab
sudo bash -c 'echo "//192.168.1.70/supabase-storage  /mnt/unraid/supabase-storage/yourdomain.com  cifs  credentials=/root/.smb-yourdomain.com.cred,iocharset=utf8  0  0" >> /etc/fstab'

# Mount
sudo mount -a

# Verify
df -h | grep supabase-storage
```

### Step 3: Edit docker-compose.yml

Edit `/srv/supabase/docker-compose.yml` and find the `storage` service:

```yaml
storage:
  # ... other config ...
  volumes:
    - /mnt/unraid/supabase-storage/yourdomain.com:/var/lib/storage
```

If the storage service has no volumes section, add it:

```yaml
storage:
  # ... other config ...
  volumes:
    - /mnt/unraid/supabase-storage/yourdomain.com:/var/lib/storage
```

### Step 4: Restart Containers

```bash
cd /srv/supabase
docker compose down
docker compose up -d

# Verify storage is mounted
docker inspect supabase-storage | grep -A 5 "Mounts"
```

### Step 5: Verify

```bash
# Check that storage container can access the mount
docker compose exec storage ls -la /var/lib/storage

# Should show the mounted Unraid storage directory contents
```

## Troubleshooting

### Storage Not Mounting

```bash
# Check if mount point exists
ls -la /mnt/unraid/supabase-storage/

# Check if Unraid is accessible
ping 192.168.1.70

# Try mounting manually to diagnose
sudo mount /mnt/unraid/supabase-storage/yourdomain.com

# Check kernel logs
dmesg | tail -20
```

### Permission Issues

```bash
# Make sure permissions are correct
sudo chmod 755 /mnt/unraid/supabase-storage/yourdomain.com
sudo chown root:root /mnt/unraid/supabase-storage/yourdomain.com

# Restart storage service
docker compose restart storage
```

### Storage Container Can't See Mount

```bash
# Check container mount
docker inspect supabase-storage | grep -A 10 Mounts

# If volume isn't showing, verify docker-compose.yml has the volume defined
grep -A 5 "storage:" /srv/supabase/docker-compose.yml
```

## Files Modified by Storage Configuration

- **`/etc/fstab`** - Added mount entry for persistent mounting
- **`/srv/supabase/docker-compose.yml`** - Updated storage service volume mount
- **`/root/.smb-*.cred`** (SMB only) - Credentials file for SMB mount

No override files are created.

