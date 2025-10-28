# Supabase Installation Improvements

Based on community best practices for self-hosting Supabase, the following enhancements have been implemented:

## 🎯 Key Improvements

### 1. Idempotent Environment File Handling

**Before:**
- `.env` values were appended, could create duplicates
- No distinction between first-time setup and updates

**After:**
- `upsert_env()` function checks if key exists and updates in-place
- Safe to re-run without creating duplicates
- Follows Supabase's recommended update pattern

**Impact:** Configuration changes are clean and repeatable

### 2. Enhanced URL Configuration

**Problem Identified:**
- Supabase requires specific URL purposes but documentation wasn't clear
- Magic link emails would break if configured with LAN IPs

**Improvements:**
- **`SITE_URL`** - Frontend URL (for email redirects, OAuth callbacks)
- **`API_EXTERNAL_URL`** - Public API gateway URL (what clients connect to)
- **`SUPABASE_PUBLIC_URL`** - Studio internal reference (synced with API_EXTERNAL_URL)
- Added clear explanations and warnings about using public URLs only

**Impact:** Better email authentication, fully functional Studio dashboard, proper API routing

### 3. JWT Secret Rotation Support

**Before:**
- No way to rotate `JWT_SECRET` without manual steps
- Rotating the secret invalidates all existing API keys (not documented)
- No automated API key regeneration

**After:**
- **Interactive pattern:** [K]eep / [G]enerate / [E]nter
- Auto-regenerates `ANON_KEY` and `SERVICE_ROLE_KEY` when JWT_SECRET changes
- Prominent warnings about client impact
- Instructions for updating client applications

**Workflow:**
```bash
sudo bash /srv/supabase/scripts/update-supabase.sh
# Select "Manage JWT secrets?" → Generate
# Script automatically regenerates API keys
# Warning displayed to update clients
```

**Impact:** Secure secret rotation capability with automatic key regeneration

### 4. Three-Action Configuration Pattern

**Before:**
- `update-supabase.sh` always asked for values
- No way to keep defaults when updating other settings

**After:**
- For each configuration section, users can:
  - **[K]eep** - Leave current value unchanged
  - **[G]enerate** - Create new secure value (secrets only)
  - **[E]nter** - Provide custom value
- Non-destructive updates

**Impact:** More flexible configuration management, safer partial updates

### 5. Separation of Concerns (Configuration Architecture)

**Implemented:**
- **Vendor files** (never modify): `docker-compose.yml`, `.env.example`
- **Host-specific config** (safe to customize): `.env`, `docker-compose.override.yml`
- Upgrade-safe design

**Benefits:**
- Official Supabase updates don't overwrite your configuration
- Clear distinction between vendor and custom settings
- Industry-standard practice for Docker Compose projects

### 6. Enhanced Installation Security

**Improvements:**
- Added critical security warnings during installation
- Documented that `.env` is never committed to git
- Explained consequences of JWT_SECRET rotation
- Security checklist in final credentials display
- All credentials stored with `chmod 600`

### 7. Updated Scripts

#### `supabase-install.sh`
✅ Improved `upsert_env()` to be properly idempotent  
✅ Added URL reference documentation  
✅ Explicit handling of `SUPABASE_PUBLIC_URL`  
✅ Security warnings about JWT rotation  
✅ Better comments explaining secret management

#### `update-supabase.sh`
✅ New helper functions: `gen_b64_url()`, `b64url()`, `gen_jwt_for_role()`  
✅ New `ask_secret_action()` for Keep/Generate/Enter pattern  
✅ JWT secret management section with auto key regeneration  
✅ Automatic `SUPABASE_PUBLIC_URL` handling  
✅ API key warnings when rotating secrets  
✅ Loads and updates `ANON_KEY` and `SERVICE_ROLE_KEY`

#### `README.md`
✅ New "Configuration Management & Best Practices" section  
✅ URL configuration reference table  
✅ JWT secret rotation guide  
✅ Environment variables documented and explained  
✅ Idempotent update workflow example  
✅ Client update instructions for key rotation

## 🔒 Security Enhancements

1. **Vendor Files Protection**
   - `.env.example` remains untouched
   - Custom `.env` created separately
   - Upgrade-safe design

2. **Secret Rotation Support**
   - Can safely rotate `JWT_SECRET` when needed
   - Automatic API key regeneration
   - Clear warnings about client impact

3. **Configuration Backups**
   - `update-supabase.sh` creates timestamped backups
   - Can rollback if needed

4. **Idempotent Updates**
   - Safe to run multiple times
   - No duplicate entries
   - Partial updates supported

## 📚 Best Practices Implemented

From Supabase's official self-hosting documentation:

✅ Leave vendor files alone (`docker-compose.yml`, `.env.example`)  
✅ Generate only two custom files: `.env` and `docker-compose.override.yml`  
✅ Show configurable values with sensible defaults  
✅ Allow Keep/Generate/Enter choices for each setting  
✅ Never ship example secrets to production  
✅ Rotate secrets in the script automatically  
✅ Use public URLs only (not LAN IPs)  
✅ Support idempotent, repeatable configuration  

## 📖 Documentation Changes

### New Sections in README

1. **Configuration Management & Best Practices**
   - File hierarchy and purposes
   - When to use what

2. **URL Configuration Reference**
   - Purpose of each URL type
   - Examples
   - Common mistakes

3. **JWT Secret Management Guide**
   - When to rotate
   - How to rotate safely
   - Client update instructions

4. **Environment Variables Documented**
   - URLs & Domains
   - Secrets (with security warnings)
   - Features & Auth settings

5. **Idempotent Updates Explanation**
   - Why it's safe to run multiple times
   - What it preserves
   - What it changes

## 🧪 Testing Checklist

- [x] Syntax validation passes
- [x] Functions properly idempotent
- [x] JWT regeneration tested with helper functions
- [x] Update script maintains backward compatibility
- [x] Configuration comments and documentation added
- [x] No breaking changes to installation process

## 🚀 Usage Examples

### Initial Installation
```bash
sudo bash supabase-install.sh
# Same as before - fully automated
```

### Update Configuration Later
```bash
sudo bash /srv/supabase/scripts/update-supabase.sh
# New: Can manage JWT secrets
# New: Keep/Generate/Enter pattern for each setting
```

### Rotate JWT Secret (New)
```bash
sudo bash /srv/supabase/scripts/update-supabase.sh
# When prompted: "Manage JWT secrets?" → yes
# Choose: [G]enerate
# Script auto-regenerates ANON_KEY and SERVICE_ROLE_KEY
# Clients need to be updated with new ANON_KEY
```

### Update Specific Setting (New)
```bash
sudo bash /srv/supabase/scripts/update-supabase.sh
# When prompted: "Update X?" → yes/no
# Keep other sections unchanged
```

## 📊 Benefits Summary

| Aspect | Before | After |
|--------|--------|-------|
| Config Updates | Always prompted for all values | Choose Keep/Generate/Enter per setting |
| JWT Rotation | Manual, error-prone | Automated with API key regeneration |
| Security | Basic | Enhanced with warnings and best practices |
| Upgrade Safety | Risk of overwriting config | Protected via separation of concerns |
| Idempotency | Limited | Full support with upsert operations |
| Documentation | Minimal | Comprehensive with examples |

## 🔄 Backward Compatibility

All improvements are **fully backward compatible**:
- Existing installations work unchanged
- Installation process identical
- New features are opt-in via update script
- No breaking changes to environment variables
- Existing `.env` files continue to work

---

**Last Updated:** October 2025  
**Based On:** Supabase Self-Hosting Docker Guide + Community Best Practices
