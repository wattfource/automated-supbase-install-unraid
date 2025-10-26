# Complete Backup & Restore Workflow

## 🎯 Three Usage Scenarios

### Scenario 1: Fresh Installation (Scripts Auto-Installed)

```bash
# Step 1: Install Supabase (utilities download automatically)
sudo bash supabase-install.sh

# Step 2: Scripts are ready to use immediately
ls /srv/supabase/scripts/
# ✓ diagnostic.sh
# ✓ update.sh
# ✓ backup-from-cloud.sh       (auto-downloaded)
# ✓ restore-database.sh         (auto-downloaded)

# Step 3: Migrate from Supabase Cloud (if needed)
sudo bash /srv/supabase/scripts/backup-from-cloud.sh --auto-restore
```

**Result:** Everything works out of the box! 🎉

---

### Scenario 2: Time Has Elapsed (Update Scripts)

If weeks/months have passed since installation, scripts may have been updated:

```bash
# One-liner: Download latest versions from repo
sudo bash -c 'cd /srv/supabase/scripts && curl -fsSL https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/backup-from-cloud.sh -o backup-from-cloud.sh && curl -fsSL https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/restore-database.sh -o restore-database.sh && chmod +x backup-from-cloud.sh restore-database.sh && echo "✓ Utilities updated"'

# Then use as normal
sudo bash /srv/supabase/scripts/backup-from-cloud.sh --auto-restore
```

**Why?** Gets latest bug fixes, features, and improvements.

---

### Scenario 3: Scripts Missing (Manual Installation)

If scripts weren't auto-installed or were deleted:

```bash
# Download both utilities
sudo bash -c 'cd /tmp && curl -fsSL https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/backup-from-cloud.sh -o backup-from-cloud.sh && curl -fsSL https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/restore-database.sh -o restore-database.sh && chmod +x backup-from-cloud.sh restore-database.sh && mv backup-from-cloud.sh restore-database.sh /srv/supabase/scripts/'

# Then use as normal
sudo bash /srv/supabase/scripts/backup-from-cloud.sh --auto-restore
```

---

## 📋 Quick Command Reference

### Auto-Download During Installation
```bash
# Happens automatically in supabase-install.sh
# Lines 1398-1420: Downloads backup-from-cloud.sh and restore-database.sh
```

### Update Utilities (After Time Has Passed)
```bash
# Downloads + overwrites with latest from repo
sudo bash -c 'cd /srv/supabase/scripts && curl -fsSL https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/backup-from-cloud.sh -o backup-from-cloud.sh && curl -fsSL https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/restore-database.sh -o restore-database.sh && chmod +x backup-from-cloud.sh restore-database.sh && echo "✓ Utilities updated"'
```

### Use Utilities
```bash
# Backup from cloud
sudo bash /srv/supabase/scripts/backup-from-cloud.sh

# Backup + restore (migration)
sudo bash /srv/supabase/scripts/backup-from-cloud.sh --auto-restore

# Restore from file
sudo bash /srv/supabase/scripts/restore-database.sh /tmp/backup.dump
```

---

## 🔄 Script Lifecycle

```
┌─────────────────────────────────────────────────────────────────┐
│  INSTALLATION (supabase-install.sh)                             │
│  ┌─────────────────────────────────────────────────┐            │
│  │  Auto-downloads utilities from GitHub           │            │
│  │  ✓ backup-from-cloud.sh                         │            │
│  │  ✓ restore-database.sh                          │            │
│  │  Placed in: /srv/supabase/scripts/              │            │
│  └─────────────────────────────────────────────────┘            │
└─────────────────────────────────────────────────────────────────┘
                           │
                           ↓
┌─────────────────────────────────────────────────────────────────┐
│  USAGE (weeks/months later)                                     │
│  ┌─────────────────────────────────────────────────┐            │
│  │  Scripts already installed and ready to use     │            │
│  │  Run: backup-from-cloud.sh or restore-database.sh           │
│  └─────────────────────────────────────────────────┘            │
└─────────────────────────────────────────────────────────────────┘
                           │
                           ↓
┌─────────────────────────────────────────────────────────────────┐
│  UPDATE (if scripts have been improved)                         │
│  ┌─────────────────────────────────────────────────┐            │
│  │  Run one-liner to download latest versions      │            │
│  │  Overwrites old files with new ones             │            │
│  │  Gets bug fixes and new features                │            │
│  └─────────────────────────────────────────────────┘            │
└─────────────────────────────────────────────────────────────────┘
                           │
                           ↓
┌─────────────────────────────────────────────────────────────────┐
│  USAGE (with updated utilities)                                 │
│  ┌─────────────────────────────────────────────────┐            │
│  │  Enhanced functionality and bug fixes            │            │
│  │  Same commands, better experience                │            │
│  └─────────────────────────────────────────────────┘            │
└─────────────────────────────────────────────────────────────────┘
```

---

## ✨ Key Benefits of This Approach

1. **Zero Setup:** Scripts auto-download during installation
2. **Always Available:** Ready to use immediately after install
3. **Easy Updates:** One-liner gets latest versions when needed
4. **Idempotent:** Safe to run update command multiple times
5. **Non-Breaking:** Updates overwrite, don't require reinstallation

---

## 📊 File Locations

```
/srv/supabase/
├── scripts/
│   ├── diagnostic.sh              (auto-created during install)
│   ├── update.sh                  (auto-created during install)
│   ├── backup-from-cloud.sh       (auto-downloaded during install)
│   └── restore-database.sh        (auto-downloaded during install)
└── backups/
    ├── cloud-backup-*.dump        (created by backup-from-cloud.sh)
    └── pre-restore-*.dump         (safety backups by restore-database.sh)
```

---

## 🎯 Best Practice Recommendation

**For Fresh Installations:**
- ✅ Just run the scripts after installation (they're already there)

**If Time Has Elapsed:**
- ✅ Run the update one-liner before important operations
- ✅ Ensures you have latest bug fixes
- ✅ Gets new features and improvements

**Example:**
```bash
# Before migrating from Supabase Cloud (after 6 months):
# 1. Update utilities first
sudo bash -c 'cd /srv/supabase/scripts && curl -fsSL https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/backup-from-cloud.sh -o backup-from-cloud.sh && curl -fsSL https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/restore-database.sh -o restore-database.sh && chmod +x backup-from-cloud.sh restore-database.sh && echo "✓ Utilities updated"'

# 2. Then migrate
sudo bash /srv/supabase/scripts/backup-from-cloud.sh --auto-restore
```

---

## 💡 Summary

| When | What to Do | Why |
|------|------------|-----|
| **Fresh Install** | Nothing - scripts auto-downloaded | Automatic, zero setup |
| **Immediate Use** | Run scripts directly | Already installed and ready |
| **Weeks/Months Later** | Run update one-liner first | Gets latest improvements |
| **Then Migrate/Backup** | Use updated scripts | Best experience, latest features |

**The update one-liner doesn't execute the scripts - it just downloads/overwrites them so you have the latest versions when you do run them!**

