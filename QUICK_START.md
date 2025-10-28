# Quick Start Guide - Enhanced Features

## 🆕 What's New

This version includes best practices from Supabase's self-hosting documentation:

### 1. JWT Secret Management ⭐ (NEW)

Safely rotate your authentication keys:

```bash
sudo bash /srv/supabase/scripts/update-supabase.sh
```

**Step by step:**
1. When asked "Manage JWT secrets?" → answer **yes**
2. Choose an action:
   - **[K]eep** - Don't change (default)
   - **[G]enerate** - Create new secure secret
   - **[E]nter** - Paste your own secret
3. Script auto-generates new API keys
4. ⚠️ **Important:** Tell your app developers to update their API keys!

### 2. Flexible Configuration Updates ⭐ (NEW)

Update only the settings you need:

```bash
sudo bash /srv/supabase/scripts/update-supabase.sh
```

For each section, you'll see:
```
Update authentication settings? [y/N]: n
Update email/SMTP settings? [y/N]: y
Update studio settings? [y/N]: n
```

**Benefit:** Change one setting without re-entering everything else.

### 3. Better URL Management

Three important URLs (explained in README):

| URL | Purpose |
|-----|---------|
| `SITE_URL` | Where your app is hosted (email redirects go here) |
| `API_EXTERNAL_URL` | Your Supabase API gateway (clients connect here) |
| `SUPABASE_PUBLIC_URL` | Studio's internal reference (same as API_EXTERNAL_URL) |

**Rule:** Always use **domain names**, never LAN IPs like `192.168.1.100`

## 📚 Documentation

All new features documented in `README.md`:
- **Configuration Management & Best Practices**
- **URL Configuration** reference
- **JWT Secret Management** guide
- **Environment Variables** explained

## 🔐 Security Improvements

✅ Vendor files stay untouched (upgrades safe)  
✅ Secrets always encrypted (`chmod 600`)  
✅ JWT rotation with auto key regeneration  
✅ Idempotent updates (safe to run multiple times)  

## 🚀 Common Tasks

### Rotate Your JWT Secret (Security)
```bash
sudo bash /srv/supabase/scripts/update-supabase.sh
# Choose: Manage JWT secrets? → yes → Generate
# Update your app with new ANON_KEY
```

### Change Domain After Launch
```bash
sudo bash /srv/supabase/scripts/update-supabase.sh
# Choose: Update authentication settings? → yes
# Enter your new SITE_URL and API_EXTERNAL_URL
```

### Change Email Provider
```bash
sudo bash /srv/supabase/scripts/update-supabase.sh
# Choose: Update email/SMTP settings? → yes
# Enter new SMTP credentials
```

### Update One Setting
```bash
sudo bash /srv/supabase/scripts/update-supabase.sh
# Answer 'no' to sections you don't want to change
# Answer 'yes' only to the section you need
# Keep all other settings unchanged
```

## ⚠️ Important: API Key Rotation

When you rotate `JWT_SECRET`, all existing API keys become invalid.

**Client update example (JavaScript):**

```javascript
// Update your app to use the new ANON_KEY
const { createClient } = require('@supabase/supabase-js')

const supabase = createClient(
  'https://api.yourdomain.com',
  'NEW_ANON_KEY_FROM_UPDATE_SCRIPT'  // ← Update this!
)
```

See `README.md` → "JWT Secret Management" for more details.

## 📋 Backup Before Major Changes

The update script creates backups automatically:

```bash
# Your backup will be created at:
/srv/supabase/.env.backup.YYYYMMDD-HHMMSS

# You can always restore:
cp /srv/supabase/.env.backup.YYYYMMDD-HHMMSS /srv/supabase/.env
docker compose restart
```

## 💡 Pro Tips

1. **Run update script regularly** - Safe to run anytime
2. **Keep backups** - Timestamped backups are automatic
3. **Document your secrets** - Save API keys securely
4. **Test changes** - Verify services after updates: `docker compose ps`
5. **Read the warnings** - Update script highlights important info

## 🆘 Need Help?

**Check logs:**
```bash
cd /srv/supabase
docker compose logs -f
```

**Run diagnostics:**
```bash
sudo bash /srv/supabase/scripts/diagnostic.sh
```

**Restore from backup:**
```bash
cd /srv/supabase
cp .env.backup.YYYYMMDD-HHMMSS .env
docker compose restart
```

---

**See `README.md` and `IMPROVEMENTS.md` for complete documentation**
