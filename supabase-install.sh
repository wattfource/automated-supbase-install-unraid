#!/usr/bin/env bash
# ============================================================================
# Supabase Self-Host Interactive Setup for Unraid Architecture
# ============================================================================
#
# ARCHITECTURE:
#   • Unraid 7 host with cache + array
#   • Debian 13 minimal VM running on Unraid cache (fast)
#   • Nginx Proxy Manager (NPM) running as Docker container on Unraid HOST
#   • Supabase containers run in the VM
#   • Supabase storage mounted from Unraid ARRAY (slow but redundant)
#
# STORAGE STRATEGY:
#   • VM & containers → Unraid cache (SSD/NVMe, fast, no redundancy needed)
#   • Supabase storage → Unraid array (HDD, slow but 1-2 disk redundancy)
#   • Mimics Supabase Cloud's S3 approach: compute fast, storage safe
#   • Array path: /mnt/user/supabase-storage/<APEX_DOMAIN>
#   • VM mount:  /mnt/unraid/supabase-storage/<APEX_DOMAIN>
#
# NETWORK:
#   • SSL terminates at NPM on Unraid HOST
#   • Only Kong:8000 and Studio:3000 exposed from VM to LAN
#   • NPM proxies to VM IP for both endpoints
#
# ROOT DIRECTORY: /srv/supabase
# ============================================================================

set -euo pipefail

bold() { printf "\033[1m%s\033[0m\n" "$*"; }
info() { printf "\033[1;36m[i]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[✓]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[✗]\033[0m %s\n" "$*" >&2; }

require_root() { [[ ${EUID:-$(id -u)} -eq 0 ]] || { err "Run as root (sudo -i)."; exit 1; }; }

ask() { local p="$1" d="${2-}" v; [[ -n "$d" ]] && read -r -p "$p [$d]: " v || read -r -p "$p: " v; echo "${v:-$d}"; }

ask_yn() {
  local p="$1" d="${2:-y}" a
  while true; do
    read -r -p "$p [${d^^}/$([ "$d" = y ] && echo n || echo y)]: " a || true
    a="${a:-$d}"; case "$a" in y|Y) echo y; return;; n|N) echo n; return;; *) warn "y or n, please.";; esac
  done
}

valid_domain() { [[ "$1" =~ ^[A-Za-z0-9.-]+$ ]] && [[ "$1" == *.* ]] && [[ "$1" != .* ]] && [[ "$1" != *..* ]]; }
ends_with_apex() { [[ "$1" == *".$2" ]]; }

upsert_env() {
  local k="$1" v="$2" esc
  esc="$(printf '%s' "$v" | sed -e 's/[&/|]/\\&/g')"
  if grep -q "^${k}=" .env 2>/dev/null; then sed -i "s|^${k}=.*|${k}=${esc}|" .env; else echo "${k}=${v}" >> .env; fi
}

gen_b64() { openssl rand -base64 "$1"; }

b64url() { openssl enc -base64 -A | tr '+/' '-_' | tr -d '='; }

gen_jwt_for_role() {
  local role="$1" header payload hb pb sig iat exp
  iat=$(date +%s); exp=$((iat + 3600*24*365*5))
  header='{"typ":"JWT","alg":"HS256"}'
  payload="$(jq -nc --arg r "$role" --argjson i "$iat" --argjson e "$exp" \
    '{"role":$r,"iss":"supabase","iat":$i,"exp":$e}')"
  hb="$(printf '%s' "$header" | b64url)"
  pb="$(printf '%s' "$payload" | b64url)"
  sig="$(printf '%s.%s' "$hb" "$pb" | openssl dgst -binary -sha256 -hmac "$JWT_SECRET" | b64url)"
  printf '%s.%s.%s\n' "$hb" "$pb" "$sig"
}

require_root

# Ensure base tools
command -v curl >/dev/null || { apt update; apt install -y curl; }
command -v gpg >/dev/null || apt install -y gpg
command -v jq   >/dev/null || apt install -y jq
command -v openssl >/dev/null || apt install -y openssl
command -v git  >/dev/null || apt install -y git

bold "Supabase Self-Host Setup → /srv/supabase"
echo
info "This will:"
echo "  • Install Docker if missing"
echo "  • Fetch official Supabase docker bundle"
echo "  • Generate secrets + JWT keys"
echo "  • Expose ONLY Kong:8000 and Studio:3000"
echo "  • Pin 8443/5432/6543 to localhost"
echo "  • Mount Unraid storage for Supabase Storage"
echo "  • (Optional) enable Analytics (Logflare)"
echo "  • (Optional) UFW/DOCKER-USER firewall hardening"
echo
warn "PROMPTS: Press Enter to accept [default: value] shown in brackets"
warn "         Fields marked REQUIRED have no default and must be entered"
echo

# Docker
if ! command -v docker >/dev/null; then
  if [[ "$(ask_yn 'Docker not found. Install Docker Engine + Compose plugin now?' y)" = y ]]; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    . /etc/os-release
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $VERSION_CODENAME stable" \
      > /etc/apt/sources.list.d/docker.list
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
    ok "Docker installed."
  else
    err "Docker required. Aborting."; exit 1
  fi
fi

# ============================================================
# DOMAIN CONFIGURATION
# ============================================================
echo
bold "1. Domain Configuration"
info "Set the domains for your Supabase instance:"
echo "  • Apex domain: Your main domain (no subdomain)"
echo "  • Kong API: All API requests go through Kong gateway (REST, Auth, Storage, etc.)"
echo "  • Studio: Web interface for managing your database, auth, storage"
echo

while :; do
  APEX_FQDN="$(ask 'Apex domain (e.g. example.com)' 'example.com')"
  if valid_domain "$APEX_FQDN" && [[ "$APEX_FQDN" != *.*.*.* ]]; then break; else err "Enter a valid apex like example.com"; fi
done

while :; do
  API_DOMAIN="$(ask "Kong API subdomain (e.g. api.example.com)" "api.${APEX_FQDN}")"
  valid_domain "$API_DOMAIN" && ends_with_apex "$API_DOMAIN" "$APEX_FQDN" && break || err "Must be a FQDN ending with .$APEX_FQDN"
done

while :; do
  STUDIO_DOMAIN="$(ask "Studio subdomain (e.g. studio.example.com)" "studio.${APEX_FQDN}")"
  valid_domain "$STUDIO_DOMAIN" && ends_with_apex "$STUDIO_DOMAIN" "$APEX_FQDN" && break || err "Must be a FQDN ending with .$APEX_FQDN"
done

# ============================================================
# PORT CONFIGURATION
# ============================================================
echo
bold "2. Port Configuration"
info "Configure which ports services listen on:"
echo "  • Kong HTTP: Main API endpoint (required, exposes to LAN)"
echo "  • Studio: Web UI port (required, exposes to LAN)"
echo "  • Kong HTTPS: Optional SSL endpoint (8443, can pin to localhost since NPM handles SSL)"
echo "  • Analytics: Logflare analytics port (4000, optional)"
echo

KONG_HTTP_PORT="$(ask 'Kong API HTTP port' '8000')"
STUDIO_PORT="$(ask 'Studio web UI port' '3000')"

# ============================================================
# SMTP CONFIGURATION
# ============================================================
echo
bold "3. Email Configuration (Optional)"
info "Configure SMTP for auth emails (signups, password resets, etc.):"
echo "  • Can be configured later by editing /srv/supabase/.env"
echo "  • Leave blank to skip for now"
echo

SMTP_HOST="$(ask 'SMTP host (optional, press Enter to skip)')"
if [[ -n "$SMTP_HOST" ]]; then
  SMTP_PORT="$(ask 'SMTP port' '587')"
  SMTP_USER="$(ask 'SMTP username' "no-reply@${APEX_FQDN}")"
  SMTP_PASS="$(ask 'SMTP password (optional, press Enter to auto-generate)')"; [[ -z "$SMTP_PASS" ]] && SMTP_PASS="$(gen_b64 24)"
  SMTP_ADMIN="$(ask 'SMTP admin email' "$SMTP_USER")"
else
  SMTP_PORT="587"; SMTP_USER="no-reply@${APEX_FQDN}"; SMTP_PASS="$(gen_b64 24)"; SMTP_ADMIN="$SMTP_USER"
fi

# ============================================================
# SECURITY CONFIGURATION
# ============================================================
echo
bold "4. Security Configuration"
echo
info "Understanding network access:"
echo "  • 'Localhost-only' (binding to 127.0.0.1): Service NOT on network, can't be reached from LAN"
echo "  • 'Network-accessible' (binding to 0.0.0.0): Service IS on network, reachable from LAN"
echo "  • 'Firewall blocking' (UFW): Service on network but firewall blocks connections"
echo
info "What we'll configure:"
echo
echo "  1. Database (5432):"
echo "     → Always internal to Docker only (never on LAN or localhost)"
echo
echo "  2. Kong HTTPS (8443):"
echo "     → Always localhost-only (NPM handles SSL, so direct HTTPS not needed)"
echo
echo "  3. Database Pooler (6543) - Supavisor for direct database connections:"
echo "     → Need to connect DB tools (DBeaver, pgAdmin, etc.) from your workstation?"
echo "     → NO (recommended): Makes it localhost-only, use 'docker exec' for DB tasks"
echo "     → YES (advanced): Leaves it network-accessible, then use UFW to restrict IPs"
echo
echo "  4. Kong HTTP (${KONG_HTTP_PORT}) & Studio (${STUDIO_PORT}):"
echo "     → Always network-accessible (NPM needs to reach them)"
echo "     → Use UFW firewall (next step) to block everyone except NPM"
echo

ENABLE_ANALYTICS="$(ask_yn 'Enable Analytics (Logflare) - makes port 4000 network-accessible?' n)"
echo
POOLER_ACCESSIBLE="$(ask_yn 'Allow database pooler (6543) from LAN for DB tools?' n)"
if [[ "$POOLER_ACCESSIBLE" = n ]]; then
  PIN_POOLER_LOOPBACK=y
  info "Pooler: localhost-only (not reachable from network)"
else
  PIN_POOLER_LOOPBACK=n
  warn "Pooler: network-accessible (configure UFW in next step!)"
fi
# Kong HTTPS always localhost-only (no option)
PIN_HTTPS_LOOPBACK=y

bold "5. Firewall Configuration (Optional but Recommended)"
echo
info "What firewall blocking does:"
echo "  • Services are still network-accessible (bound to 0.0.0.0)"
echo "  • Firewall sits in front and blocks unauthorized connections"
echo "  • Like a bouncer: service is there, but most people can't get in"
echo
info "What we'll block with UFW:"
echo "  • Kong HTTP (${KONG_HTTP_PORT}): Only NPM can connect"
echo "  • Studio (${STUDIO_PORT}): Only NPM can connect"
[[ "$PIN_POOLER_LOOPBACK" = n ]] && echo "  • Database Pooler (6543): Only specific IPs can connect (you'll set this)"
echo "  • SSH (22): Only your admin subnet can connect"
echo "  • Everything else: Allowed outbound, denied inbound"
echo
echo "Recommended for: Any network you don't fully control"
echo "Skip if: Trusted home LAN with only family members"
echo

USE_UFW="$(ask_yn 'Configure UFW firewall rules?' n)"
if [[ "$USE_UFW" = y ]]; then
  NPM_HOST_IP="$(ask 'Unraid NPM host IP (REQUIRED, e.g. 192.168.1.75)')"
  ADMIN_SSH_SRC="$(ask 'Admin IP/subnet for SSH' '192.168.1.0/24')"
  if [[ "$PIN_POOLER_LOOPBACK" = n ]]; then
    POOLER_ALLOWED_IPS="$(ask 'Database pooler allowed IPs/subnet (e.g. 192.168.1.0/24)' '192.168.1.0/24')"
  fi
fi

# ============================================================
# STORAGE CONFIGURATION
# ============================================================
echo
bold "6. Unraid Storage Mount Configuration"
info "Mount Unraid array storage for Supabase user files:"
echo "  • VM/containers run on cache (fast SSD/NVMe)"
echo "  • User uploaded files stored on array (slow HDD but parity-protected)"
echo "  • Mimics Supabase Cloud's S3 architecture: compute fast, storage safe"
echo "  • NFS: Simpler, no credentials, good for trusted LANs (recommended)"
echo "  • SMB/CIFS: Requires username/password, more compatible"
echo
echo "Mount point will be: /mnt/unraid/supabase-storage/${APEX_FQDN}"
echo

STORAGE_PROTO="$(ask 'Storage protocol: nfs or smb?' 'nfs')"
if [[ "$STORAGE_PROTO" = "nfs" ]]; then
  apt install -y nfs-common >/dev/null
  UNRAID_HOST="$(ask 'Unraid server hostname or IP' 'unraid.lan')"
  UNRAID_EXPORT="/mnt/user/supabase-storage/${APEX_FQDN}"
  VM_MOUNT="/mnt/unraid/supabase-storage/${APEX_FQDN}"
else
  apt install -y cifs-utils >/dev/null
  UNRAID_HOST="$(ask 'Unraid server hostname or IP' 'unraid.lan')"
  UNRAID_SHARE="supabase-storage"  # parent share
  UNRAID_SUBDIR="${APEX_FQDN}"     # subdirectory
  VM_MOUNT="/mnt/unraid/supabase-storage/${APEX_FQDN}"
  SMB_USER="$(ask 'SMB username (REQUIRED)')"
  SMB_PASS="$(ask 'SMB password (REQUIRED)')"
fi

echo
bold "=== Configuration Summary ==="
echo "  Apex domain:    $APEX_FQDN"
echo "  Kong API:       https://$API_DOMAIN  → VM:${KONG_HTTP_PORT} (HTTP)"
echo "  Studio:         https://$STUDIO_DOMAIN → VM:${STUDIO_PORT} (HTTP)"
echo
echo "  Network Access:"
echo "    Kong HTTP:    Network-accessible (port ${KONG_HTTP_PORT})"
echo "    Studio:       Network-accessible (port ${STUDIO_PORT})"
echo "    Kong HTTPS:   Localhost-only (port 8443)"
echo "    DB Pooler:    $( [[ "$PIN_POOLER_LOOPBACK" = y ]] && echo "Localhost-only (port 6543)" || echo "Network-accessible (port 6543)" )"
echo "    Database:     Internal to Docker only (port 5432)"
echo "    Analytics:    $( [[ "$ENABLE_ANALYTICS" = y ]] && echo "Network-accessible (port 4000)" || echo "Disabled" )"
echo
if [[ "$USE_UFW" = y ]]; then
  echo "  Firewall (UFW):"
  echo "    → NPM $NPM_HOST_IP can access Kong/Studio"
  echo "    → SSH from $ADMIN_SSH_SRC"
  [[ "$PIN_POOLER_LOOPBACK" = n ]] && echo "    → DB Pooler from $POOLER_ALLOWED_IPS"
  echo "    → All other inbound: BLOCKED"
else
  echo "  Firewall:       Not configured (open LAN access)"
fi
echo
echo "  Storage:        Unraid → VM mount at $VM_MOUNT ($STORAGE_PROTO)"
echo
[[ "$(ask_yn 'Proceed with setup?' y)" = y ]] || { err "Aborted."; exit 1; }

# Layout
ROOT="/srv/supabase"
mkdir -p "$ROOT"
cd "$ROOT"

# Fetch official bundle if missing
if [[ ! -f docker-compose.yml ]]; then
  info "Fetching Supabase official docker bundle (sparse checkout: docker/ only)..."
  rm -rf /tmp/supabase
  mkdir -p /tmp/supabase
  cd /tmp/supabase
  git init
  git remote add origin https://github.com/supabase/supabase
  git config core.sparseCheckout true
  echo "docker/*" >> .git/info/sparse-checkout
  git pull --depth 1 origin master
  cd "$ROOT"
  cp -rf /tmp/supabase/docker/* "$ROOT"/
  cp /tmp/supabase/docker/.env.example "$ROOT"/.env || touch "$ROOT/.env"
  rm -rf /tmp/supabase
  ok "Bundle copied."
else
  warn "docker-compose.yml exists; skipping fetch."
fi

# Env backup
cp -a .env ".env.bak.$(date +%F-%H%M%S)"

# Secrets & env
info "Generating secrets and writing .env ..."
POSTGRES_PASSWORD="$(gen_b64 32)"
JWT_SECRET="$(gen_b64 48)"
PG_META_CRYPTO_KEY="$(gen_b64 32)"

upsert_env SUPABASE_PUBLIC_URL "https://$API_DOMAIN"
upsert_env SITE_URL            "https://$STUDIO_DOMAIN"
upsert_env POSTGRES_PASSWORD   "$POSTGRES_PASSWORD"
upsert_env JWT_SECRET          "$JWT_SECRET"
upsert_env PG_META_CRYPTO_KEY  "$PG_META_CRYPTO_KEY"

if [[ -n "${SMTP_HOST}" ]]; then
  upsert_env GOTRUE_SMTP_HOST "$SMTP_HOST"
else
  upsert_env GOTRUE_SMTP_HOST "smtp.yourmail.tld"
fi
upsert_env GOTRUE_SMTP_PORT        "$SMTP_PORT"
upsert_env GOTRUE_SMTP_USER        "$SMTP_USER"
upsert_env GOTRUE_SMTP_PASS        "$SMTP_PASS"
upsert_env GOTRUE_SMTP_ADMIN_EMAIL "$SMTP_ADMIN"
upsert_env ENABLE_EMAIL_AUTOCONFIRM "false"

upsert_env FILE_SIZE_LIMIT "524288000"
upsert_env STORAGE_BACKEND "file"

# Pin ports (compose respects these envs)
# Note: POSTGRES_PORT is the DB's internal port, not Docker mapping - always 5432
upsert_env KONG_HTTP_PORT "0.0.0.0:${KONG_HTTP_PORT}"
[[ "$PIN_HTTPS_LOOPBACK" = y ]] && upsert_env KONG_HTTPS_PORT "127.0.0.1:8443" || upsert_env KONG_HTTPS_PORT "0.0.0.0:8443"

# Supavisor pooler ports (optional exposure)
if [[ "$PIN_POOLER_LOOPBACK" = y ]]; then
  upsert_env POOLER_PROXY_PORT_TRANSACTION "127.0.0.1:6543"
else
  upsert_env POOLER_PROXY_PORT_TRANSACTION "0.0.0.0:6543"
fi

chmod 600 .env

# JWT keys
info "Generating ANON_KEY and SERVICE_ROLE_KEY ..."
export JWT_SECRET
ANON_KEY="$(gen_jwt_for_role anon)"
SERVICE_ROLE_KEY="$(gen_jwt_for_role service_role)"
unset JWT_SECRET
upsert_env ANON_KEY "$ANON_KEY"
upsert_env SERVICE_ROLE_KEY "$SERVICE_ROLE_KEY"
ok "JWT keys added to .env"

# Storage mount (Unraid)
info "Preparing storage mount at $VM_MOUNT ..."
mkdir -p "$VM_MOUNT"
if [[ "$STORAGE_PROTO" = "nfs" ]]; then
  grep -qE "[[:space:]]$VM_MOUNT[[:space:]]" /etc/fstab || \
    echo "${UNRAID_HOST}:${UNRAID_EXPORT}  ${VM_MOUNT}  nfs  defaults  0  0" >> /etc/fstab
  mount -a || true
else
  CREDF="/root/.smb-${APEX_FQDN}.cred"
  { echo "username=${SMB_USER}"; echo "password=${SMB_PASS}"; } > "$CREDF"
  chmod 600 "$CREDF"
  grep -qE "[[:space:]]$VM_MOUNT[[:space:]]" /etc/fstab || \
    echo "//${UNRAID_HOST}/${UNRAID_SHARE}/${UNRAID_SUBDIR}  ${VM_MOUNT}  cifs  credentials=${CREDF},iocharset=utf8,file_mode=0644,dir_mode=0755,noperm  0  0" >> /etc/fstab
  mount -a || true
fi
ok "Storage mounted (check: df -h | grep supabase-storage)."

# Compose override: expose only API/Studio, wire storage volume
info "Writing docker-compose.override.yml ..."
cat > docker-compose.override.yml <<YAML
services:
  # Publish ONLY Kong API
  kong:
    ports:
      - "0.0.0.0:${KONG_HTTP_PORT}:8000"

  # Publish ONLY Studio
  studio:
    ports:
      - "0.0.0.0:${STUDIO_PORT}:3000"

  # keep others internal
  supavisor:
    ports: []
  db:
    ports: []
  auth:
    ports: []
  rest:
    ports: []
  realtime:
    ports: []

  # Analytics: only publish port if enabled
  analytics:
    ports: $( [[ "$ENABLE_ANALYTICS" = y ]] && echo '["0.0.0.0:4000:4000"]' || echo '[]' )

  storage:
    ports: []
    volumes:
      - ${VM_MOUNT}:/var/lib/storage
YAML

[[ "$ENABLE_ANALYTICS" = y ]] && warn "Analytics enabled: publishes port 4000 to LAN."

ok "Override written."

# Start stack
info "Starting Supabase containers ..."
docker compose pull
docker compose up -d
# Recreate key services to ensure port pins applied
docker compose rm -sf kong supavisor >/dev/null 2>&1 || true
docker compose up -d kong supavisor studio storage

ok "Containers started."
echo
docker compose ps

# Optional firewall
if [[ "$USE_UFW" = y ]]; then
  info "Configuring UFW + DOCKER-USER firewall rules..."
  apt install -y ufw iptables-persistent >/dev/null
  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing
  
  # SSH access from admin subnet
  ufw allow from "$ADMIN_SSH_SRC" to any port 22 proto tcp
  
  # Kong and Studio: only NPM can access
  ufw allow from "$NPM_HOST_IP" to any port "$KONG_HTTP_PORT" proto tcp
  ufw allow from "$NPM_HOST_IP" to any port "$STUDIO_PORT" proto tcp
  
  # Database pooler: only if network-accessible
  if [[ "$PIN_POOLER_LOOPBACK" = n ]]; then
    ufw allow from "$POOLER_ALLOWED_IPS" to any port 6543 proto tcp
  fi
  
  ufw --force enable
  ok "UFW rules applied."

  info "Configuring Docker-specific iptables rules..."
  # Kong and Studio: allow NPM, drop all others
  iptables -I DOCKER-USER -s "$NPM_HOST_IP" -p tcp --dport "$KONG_HTTP_PORT" -j ACCEPT
  iptables -I DOCKER-USER -s "$NPM_HOST_IP" -p tcp --dport "$STUDIO_PORT" -j ACCEPT
  iptables -I DOCKER-USER -p tcp --dport "$KONG_HTTP_PORT" -j DROP
  iptables -I DOCKER-USER -p tcp --dport "$STUDIO_PORT" -j DROP
  
  # Always block Kong HTTPS (it's localhost-only anyway)
  iptables -I DOCKER-USER -p tcp --dport 8443 -j DROP
  
  # Database pooler: allow if network-accessible, block otherwise
  if [[ "$PIN_POOLER_LOOPBACK" = n ]]; then
    iptables -I DOCKER-USER -s "$POOLER_ALLOWED_IPS" -p tcp --dport 6543 -j ACCEPT
    iptables -I DOCKER-USER -p tcp --dport 6543 -j DROP
  else
    iptables -I DOCKER-USER -p tcp --dport 6543 -j DROP
  fi
  
  # Block Analytics port (internal use only)
  iptables -I DOCKER-USER -p tcp --dport 4000 -j DROP
  
  netfilter-persistent save >/dev/null
  ok "Docker firewall rules applied and saved."
fi

# Final notes
echo
bold "Done! Next steps"
cat <<EOF
1) In Nginx Proxy Manager on Unraid, create two Proxy Hosts:
   - ${API_DOMAIN}    →  http://localhost:${KONG_HTTP_PORT}  (Enable Websockets; SSL at NPM)
   - ${STUDIO_DOMAIN} →  http://localhost:${STUDIO_PORT}  (Protect with Access List/IP allowlist)

2) Verify storage mount:
   VM path: ${VM_MOUNT}
   Inside 'storage' container: /var/lib/storage
   Test: docker compose exec storage ls -l /var/lib/storage

3) Email:
   Update SMTP in .env if placeholders, then: docker compose up -d auth

4) Backups (safe):
   cd /srv/supabase
   mkdir -p backups
   docker compose exec -T db pg_dump -U postgres -Fc -d postgres > "backups/\$(date +%F_%H-%M).dump"

5) Update stack:
   docker compose pull && docker compose up -d

Files:
  • Project: /srv/supabase
  • Storage mount: ${VM_MOUNT}  (from Unraid ${STORAGE_PROTO})
  • Ports: Kong=${KONG_HTTP_PORT}, Studio=${STUDIO_PORT}
EOF

ok "Supabase is up. Visit: https://${STUDIO_DOMAIN} (Studio) and use https://${API_DOMAIN} in your app."
