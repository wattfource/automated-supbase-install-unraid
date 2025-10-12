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
command -v curl >/dev/null || apt update
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

# Inputs (clear wording)
while :; do
  APEX_FQDN="$(ask 'Apex domain (no subdomain), e.g. example.com' 'example.com')"
  if valid_domain "$APEX_FQDN" && [[ "$APEX_FQDN" != *.*.*.* ]]; then break; else err "Enter a valid apex like example.com"; fi
done

while :; do
  API_DOMAIN="$(ask 'API hostname (FQDN), e.g. api.example.com' "api.${APEX_FQDN}")"
  valid_domain "$API_DOMAIN" && ends_with_apex "$API_DOMAIN" "$APEX_FQDN" && break || err "Must be a FQDN ending with .$APEX_FQDN"
done

while :; do
  STUDIO_DOMAIN="$(ask 'Studio hostname (FQDN), e.g. studio.example.com' "studio.${APEX_FQDN}")"
  valid_domain "$STUDIO_DOMAIN" && ends_with_apex "$STUDIO_DOMAIN" "$APEX_FQDN" && break || err "Must be a FQDN ending with .$APEX_FQDN"
done

SMTP_HOST="$(ask 'SMTP host (leave empty to set placeholder and change later)')"
if [[ -n "$SMTP_HOST" ]]; then
  SMTP_PORT="$(ask 'SMTP port' '587')"
  SMTP_USER="$(ask 'SMTP username' "no-reply@${APEX_FQDN}")"
  SMTP_PASS="$(ask 'SMTP password (empty to auto-generate)')"; [[ -z "$SMTP_PASS" ]] && SMTP_PASS="$(gen_b64 24)"
  SMTP_ADMIN="$(ask 'SMTP admin email' "$SMTP_USER")"
else
  SMTP_PORT="587"; SMTP_USER="no-reply@${APEX_FQDN}"; SMTP_PASS="$(gen_b64 24)"; SMTP_ADMIN="$SMTP_USER"
fi

ENABLE_ANALYTICS="$(ask_yn 'Enable Analytics (Logflare) (publishes 4000 to LAN)' n)"
PIN_HTTPS_LOOPBACK="$(ask_yn 'Pin Kong HTTPS 8443 to localhost (recommended)' y)"
PIN_POOLER_LOOPBACK="$(ask_yn 'Pin Supavisor 5432/6543 to localhost (recommended)' y)"

USE_UFW="$(ask_yn 'Configure UFW + DOCKER-USER rules to only allow your NPM host to 8000/3000?' n)"
if [[ "$USE_UFW" = y ]]; then
  NPM_HOST_IP="$(ask 'Unraid NPM host IP (e.g., 192.168.1.75)')"
  ADMIN_SSH_SRC="$(ask 'Admin IP/subnet for SSH (e.g., 192.168.1.0/24)' '192.168.1.0/24')"
fi

# Storage mount choice
bold "Unraid Storage Mount"
echo "We will mount your Unraid storage at: /mnt/unraid/supabase-storage/${APEX_FQDN}"
STORAGE_PROTO="$(ask 'Storage protocol (nfs|smb)' 'nfs')"
if [[ "$STORAGE_PROTO" = "nfs" ]]; then
  apt install -y nfs-common >/dev/null
  UNRAID_HOST="$(ask 'Unraid server hostname/IP' 'unraid.lan')"
  UNRAID_EXPORT="/mnt/user/supabase-storage/${APEX_FQDN}"
  VM_MOUNT="/mnt/unraid/supabase-storage/${APEX_FQDN}"
else
  apt install -y cifs-utils >/dev/null
  UNRAID_HOST="$(ask 'Unraid server hostname/IP' 'unraid.lan')"
  UNRAID_SHARE="supabase-storage"  # parent share
  UNRAID_SUBDIR="${APEX_FQDN}"     # subdirectory
  VM_MOUNT="/mnt/unraid/supabase-storage/${APEX_FQDN}"
  SMB_USER="$(ask 'SMB username')"
  SMB_PASS="$(ask 'SMB password')"
fi

echo
bold "Summary"
echo "  Apex domain:  $APEX_FQDN"
echo "  API:          https://$API_DOMAIN  → VM:8000 (HTTP)"
echo "  Studio:       https://$STUDIO_DOMAIN → VM:3000 (HTTP)"
echo "  Analytics:    $( [[ "$ENABLE_ANALYTICS" = y ]] && echo ENABLED || echo DISABLED )"
echo "  HTTPS pin:    $( [[ "$PIN_HTTPS_LOOPBACK" = y ]] && echo 127.0.0.1:8443 || echo LAN-exposed per base )"
echo "  Pooler pin:   $( [[ "$PIN_POOLER_LOOPBACK" = y ]] && echo 127.0.0.1:5432/6543 || echo LAN-exposed per base )"
echo "  Storage:      Unraid → VM mount at $VM_MOUNT ($STORAGE_PROTO)"
[[ "$USE_UFW" = y ]] && echo "  Firewall:     NPM $NPM_HOST_IP allowed to 8000/3000; SSH from $ADMIN_SSH_SRC"
echo
[[ "$(ask_yn 'Proceed with setup?' y)" = y ]] || { err "Aborted."; exit 1; }

# Layout
ROOT="/srv/supabase"
mkdir -p "$ROOT"
cd "$ROOT"

# Fetch official bundle if missing
if [[ ! -f docker-compose.yml ]]; then
  info "Fetching Supabase official docker bundle..."
  rm -rf /tmp/supabase
  git clone --depth 1 https://github.com/supabase/supabase /tmp/supabase
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
upsert_env KONG_HTTP_PORT "0.0.0.0:8000"
[[ "$PIN_HTTPS_LOOPBACK" = y ]] && upsert_env KONG_HTTPS_PORT "127.0.0.1:8443"
if [[ "$PIN_POOLER_LOOPBACK" = y ]]; then
  upsert_env POSTGRES_PORT "127.0.0.1:5432"
  upsert_env POOLER_PROXY_PORT_TRANSACTION "127.0.0.1:6543"
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
  # Publish ONLY API 8000
  kong:
    ports:
      - "0.0.0.0:8000:8000"

  # Publish ONLY Studio 3000
  studio:
    ports:
      - "0.0.0.0:3000:3000"

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

  storage:
    ports: []
    volumes:
      - ${VM_MOUNT}:/var/lib/storage
YAML

if [[ "$ENABLE_ANALYTICS" = y ]]; then
  warn "Analytics enabled: upstream publishes 4000 to LAN."
else
  cat >> docker-compose.override.yml <<'YAML'

  analytics:
    profiles: ["dev"]   # disabled by default; enable later with COMPOSE_PROFILES=dev
YAML
fi

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
  info "Configuring UFW + DOCKER-USER ..."
  apt install -y ufw iptables-persistent >/dev/null
  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow from "$ADMIN_SSH_SRC" to any port 22 proto tcp
  ufw allow from "$NPM_HOST_IP" to any port 8000 proto tcp
  ufw allow from "$NPM_HOST_IP" to any port 3000 proto tcp
  ufw --force enable

  iptables -I DOCKER-USER -s "$NPM_HOST_IP" -p tcp --dport 8000 -j ACCEPT
  iptables -I DOCKER-USER -s "$NPM_HOST_IP" -p tcp --dport 3000 -j ACCEPT
  iptables -I DOCKER-USER -p tcp --dport 8000 -j DROP
  iptables -I DOCKER-USER -p tcp --dport 3000 -j DROP
  iptables -I DOCKER-USER -p tcp --dport 8443 -j DROP
  iptables -I DOCKER-USER -p tcp --dport 5432 -j DROP
  iptables -I DOCKER-USER -p tcp --dport 6543 -j DROP
  iptables -I DOCKER-USER -p tcp --dport 4000 -j DROP
  netfilter-persistent save >/dev/null
  ok "Firewall rules applied."
fi

# Final notes
echo
bold "Done! Next steps"
cat <<EOF
1) In Nginx Proxy Manager on Unraid, create two Proxy Hosts:
   - ${API_DOMAIN}    →  http://<VM-IP>:8000  (Enable Websockets; SSL at NPM)
   - ${STUDIO_DOMAIN} →  http://<VM-IP>:3000  (Protect with Access List/IP allowlist)

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
EOF

ok "Supabase is up. Visit: https://${STUDIO_DOMAIN} (Studio) and use https://${API_DOMAIN} in your app."
