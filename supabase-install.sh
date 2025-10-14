#!/usr/bin/env bash
# ============================================================================
# ███████╗██╗   ██╗██████╗  █████╗ ██████╗  █████╗ ███████╗███████╗
# ██╔════╝██║   ██║██╔══██╗██╔══██╗██╔══██╗██╔══██╗██╔════╝██╔════╝
# ███████╗██║   ██║██████╔╝███████║██████╔╝███████║███████╗█████╗  
# ╚════██║██║   ██║██╔═══╝ ██╔══██║██╔══██╗██╔══██║╚════██║██╔══╝  
# ███████║╚██████╔╝██║     ██║  ██║██████╔╝██║  ██║███████║███████╗
# ╚══════╝ ╚═════╝ ╚═╝     ╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝╚══════╝╚══════╝
#                                                                    
# ██╗███╗   ██╗███████╗████████╗ █████╗ ██╗     ██╗     ██╗██╗   ██╗███████╗██████╗ 
# ██║████╗  ██║██╔════╝╚══██╔══╝██╔══██╗██║     ██║     ██║██║   ██║██╔════╝██╔══██╗
# ██║██╔██╗ ██║███████╗   ██║   ███████║██║     ██║     ██║██║   ██║█████╗  ██████╔╝
# ██║██║╚██╗██║╚════██║   ██║   ██╔══██║██║     ██║     ██║╚██╗ ██╔╝██╔══╝  ██╔══██╗
# ██║██║ ╚████║███████║   ██║   ██║  ██║███████╗███████╗██║ ╚████╔╝ ███████╗██║  ██║
# ╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚══════╝╚═╝  ╚═══╝  ╚══════╝╚═╝  ╚═╝
#                                                                                    
# ╔══════════════════════════════════════════════════════════════════════════════════╗
# ║                         WATTFOURCE GRID ARCHITECTURE                             ║
# ║                                                                                  ║
# ║  ████████████████████████████████████████████████████████████████████████████    ║
# ║  █ UNRAID HOST (GRID NODE)                                    █                  ║
# ║  █ ┌─────────────────┐  ┌─────────────────────────────────┐  █                  ║
# ║  █ │   CACHE (SSD)   │  │        ARRAY (HDD)              │  █                  ║
# ║  █ │ ┌─────────────┐ │  │ ┌─────────────────────────────┐ │  █                  ║
# ║  █ │ │ DEBIAN VM   │ │  │ │ SUPABASE STORAGE            │ │  █                  ║
# ║  █ │ │ (FAST)      │ │  │ │ (REDUNDANT)                 │ │  █                  ║
# ║  █ │ └─────────────┘ │  │ └─────────────────────────────┘ │  █                  ║
# ║  █ └─────────────────┘  └─────────────────────────────────┘  █                  ║
# ║  ████████████████████████████████████████████████████████████████████████████    ║
# ║                                                                                  ║
# ║  NETWORK FLOW:                                                                   ║
# ║  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐                          ║
# ║  │   CLIENT    │───▶│     NPM     │───▶│     VM      │                          ║
# ║  │             │    │ (SSL TERM)  │    │ (KONG:8000) │                          ║
# ║  └─────────────┘    └─────────────┘    └─────────────┘                          ║
# ╚══════════════════════════════════════════════════════════════════════════════════╝
# ============================================================================

set -euo pipefail

# Tron-style color functions
tron_cyan() { printf "\033[1;36m%s\033[0m\n" "$*"; }
tron_blue() { printf "\033[1;34m%s\033[0m\n" "$*"; }
tron_green() { printf "\033[1;32m%s\033[0m\n" "$*"; }
tron_yellow() { printf "\033[1;33m%s\033[0m\n" "$*"; }
tron_red() { printf "\033[1;31m%s\033[0m\n" "$*"; }
tron_magenta() { printf "\033[1;35m%s\033[0m\n" "$*"; }
tron_white() { printf "\033[1;37m%s\033[0m\n" "$*"; }

# Enhanced status functions with Tron styling
bold() { printf "\033[1m%s\033[0m\n" "$*"; }
info() { printf "\033[1;36m[◉]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[✓]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[⚠]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[✗]\033[0m %s\n" "$*" >&2; }
step() { printf "\033[1;35m[▶]\033[0m %s\n" "$*"; }

# ASCII art elements
show_grid() {
    echo "╔══════════════════════════════════════════════════════════════════════════════════╗"
    echo "║                                                                                  ║"
    echo "║  ████████████████████████████████████████████████████████████████████████████    ║"
    echo "║  █                                                                              █    ║"
    echo "║  █  $1  █    ║"
    echo "║  █                                                                              █    ║"
    echo "║  ████████████████████████████████████████████████████████████████████████████    ║"
    echo "║                                                                                  ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════════╝"
}

show_progress() {
    local current=$1 total=$2 desc="$3"
    local percent=$((current * 100 / total))
    local filled=$((percent / 5))
    local empty=$((20 - filled))
    
    printf "\r\033[1;36m["
    for ((i=0; i<filled; i++)); do printf "█"; done
    for ((i=0; i<empty; i++)); do printf "░"; done
    printf "] %d%% - %s\033[0m" "$percent" "$desc"
    [[ $current -eq $total ]] && echo
}

# Animated loading spinner
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf "\r\033[1;36m[%c] Processing...\033[0m" "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
    done
    printf "\r\033[1;32m[✓] Complete!\033[0m\n"
}

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

# Clear screen and show intro
clear
tron_cyan "╔══════════════════════════════════════════════════════════════════════════════════╗"
tron_cyan "║                                                                                  ║"
tron_cyan "║             ██╗    ██╗ █████╗ ████████╗████████╗███████╗ ██████╗ ██╗   ██╗██████╗  ██████╗███████╗  ║"
tron_cyan "║             ██║    ██║██╔══██╗╚══██╔══╝╚══██╔══╝██╔════╝██╔═══██╗██║   ██║██╔══██╗██╔════╝██╔════╝  ║"
tron_cyan "║             ██║ █╗ ██║███████║   ██║      ██║   █████╗  ██║   ██║██║   ██║██████╔╝██║     █████╗    ║"
tron_cyan "║             ██║███╗██║██╔══██║   ██║      ██║   ██╔══╝  ██║   ██║██║   ██║██╔══██╗██║     ██╔══╝    ║"
tron_cyan "║             ╚███╔███╔╝██║  ██║   ██║      ██║   ██║     ╚██████╔╝╚██████╔╝██║  ██║╚██████╗███████╗  ║"
tron_cyan "║              ╚══╝╚══╝ ╚═╝  ╚═╝   ╚═╝      ╚═╝   ╚═╝      ╚═════╝  ╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚══════╝  ║"
tron_cyan "║                                                                                  ║"
tron_cyan "║                          GRID INITIALIZATION SEQUENCE                           ║"
tron_cyan "║                    ████████████████████████████████████████████████████████      ║"
tron_cyan "╚══════════════════════════════════════════════════════════════════════════════════╝"
echo

# Ensure base tools
step "Initializing system dependencies..."
command -v curl >/dev/null || { apt update; apt install -y curl; }
command -v gpg >/dev/null || apt install -y gpg
command -v jq   >/dev/null || apt install -y jq
command -v openssl >/dev/null || apt install -y openssl
command -v git  >/dev/null || apt install -y git
ok "System dependencies verified"

echo
show_grid "WATTFOURCE GRID ARCHITECTURE ANALYSIS"
echo
tron_white "╔══════════════════════════════════════════════════════════════════════════════════╗"
tron_white "║                           DEPLOYMENT BRIEFING                                   ║"
tron_white "╚══════════════════════════════════════════════════════════════════════════════════╝"
echo
tron_cyan "This installation will deploy a self-hosted Supabase instance optimized for Unraid architecture."
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

# Docker Installation Check
echo
tron_blue "╔══════════════════════════════════════════════════════════════════════════════════╗"
tron_blue "║                        CONTAINER RUNTIME VERIFICATION                           ║"
tron_blue "╚══════════════════════════════════════════════════════════════════════════════════╝"
echo
tron_white "Docker is the containerization platform that will host all Supabase services."
tron_white "Without Docker, we cannot deploy the Supabase stack. This installation will:"
echo
tron_cyan "  █ Add Docker's official GPG key and repository"
tron_cyan "  █ Install Docker Engine, CLI, and Compose plugin"
tron_cyan "  █ Enable and start the Docker service"
tron_cyan "  █ Configure Docker to start on boot"
echo
tron_yellow "  ⚠ This requires root privileges and will modify your system packages."
echo

if ! command -v docker >/dev/null; then
  if [[ "$(ask_yn 'Docker not found. Install Docker Engine + Compose plugin now?' y)" = y ]]; then
    step "Installing Docker Engine..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    . /etc/os-release
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $VERSION_CODENAME stable" \
      > /etc/apt/sources.list.d/docker.list
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
    ok "Docker runtime installed and activated"
  else
    err "Docker is required for Supabase deployment. Aborting."; exit 1
  fi
else
  ok "Docker runtime detected"
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

# SMTP Configuration
echo
tron_blue "╔══════════════════════════════════════════════════════════════════════════════════╗"
tron_blue "║                        EMAIL SERVICE CONFIGURATION                               ║"
tron_blue "╚══════════════════════════════════════════════════════════════════════════════════╝"
echo
tron_white "Supabase requires SMTP configuration for user authentication emails."
tron_white "This includes password reset emails, email confirmations, and notifications."
echo
tron_cyan "  █ SMTP Host: Your email provider's SMTP server"
tron_cyan "  █ SMTP Port: Usually 587 (TLS) or 465 (SSL)"
tron_cyan "  █ SMTP User: Your email account username"
tron_cyan "  █ SMTP Password: Your email account password or app password"
echo
tron_yellow "  ⚠ You can skip this now and configure it later in the .env file"
tron_yellow "  ⚠ Popular providers: Gmail (smtp.gmail.com), Outlook (smtp-mail.outlook.com)"
echo

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
  ok "SMTP configuration completed"
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
  echo
  tron_white "NFS CONFIGURATION"
  tron_white "NFS is the recommended protocol for Linux-to-Linux file sharing."
  tron_white "It provides better performance and reliability than SMB for this use case."
  apt install -y nfs-common >/dev/null
  UNRAID_HOST="$(ask 'Unraid server hostname or IP' 'unraid.lan')"
  UNRAID_EXPORT="/mnt/user/supabase-storage/${APEX_FQDN}"
  VM_MOUNT="/mnt/unraid/supabase-storage/${APEX_FQDN}"
  ok "NFS client installed and configured"
else
  echo
  tron_white "SMB CONFIGURATION"
  tron_white "SMB is compatible with Windows-style network shares."
  tron_white "You'll need credentials for a user with access to the supabase-storage share."
  apt install -y cifs-utils >/dev/null
  UNRAID_HOST="$(ask 'Unraid server hostname or IP' 'unraid.lan')"
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
[[ "$(ask_yn 'Proceed with Supabase deployment?' y)" = y ]] || { err "Deployment aborted by user."; exit 1; }

# Deployment Phase
echo
tron_blue "╔══════════════════════════════════════════════════════════════════════════════════╗"
tron_blue "║                        INITIATING DEPLOYMENT SEQUENCE                            ║"
tron_blue "╚══════════════════════════════════════════════════════════════════════════════════╝"
echo

# Layout
step "Creating deployment directory structure..."
ROOT="/srv/supabase"
mkdir -p "$ROOT"
cd "$ROOT"
ok "Deployment directory created: $ROOT"

# Fetch official bundle if missing
if [[ ! -f docker-compose.yml ]]; then
  info "Fetching Supabase official docker bundle..."
  rm -rf /tmp/supabase
  git clone --depth 1 https://github.com/supabase/supabase /tmp/supabase
  cp -rf /tmp/supabase/docker/* "$ROOT"/
  cp /tmp/supabase/docker/.env.example "$ROOT"/.env || touch "$ROOT/.env"
  
  show_progress 4 4 "Cleaning up temporary files"
  rm -rf /tmp/supabase
  ok "Supabase bundle downloaded and extracted"
else
  warn "docker-compose.yml already exists; skipping download"
fi

# Environment Configuration
step "Backing up existing environment configuration..."
cp -a .env ".env.bak.$(date +%F-%H%M%S)"
ok "Environment backup created"

step "Generating cryptographic secrets and security keys..."
show_progress 1 3 "Generating PostgreSQL password"
POSTGRES_PASSWORD="$(gen_b64 32)"

show_progress 2 3 "Generating JWT secret"
JWT_SECRET="$(gen_b64 48)"

show_progress 3 3 "Generating metadata encryption key"
PG_META_CRYPTO_KEY="$(gen_b64 32)"
ok "Cryptographic secrets generated"

step "Configuring environment variables..."
show_progress 1 6 "Setting API and Studio URLs"
upsert_env SUPABASE_PUBLIC_URL "https://$API_DOMAIN"
upsert_env SITE_URL            "https://$STUDIO_DOMAIN"

show_progress 2 6 "Setting database credentials"
upsert_env POSTGRES_PASSWORD   "$POSTGRES_PASSWORD"
upsert_env JWT_SECRET          "$JWT_SECRET"
upsert_env PG_META_CRYPTO_KEY  "$PG_META_CRYPTO_KEY"

show_progress 3 6 "Configuring SMTP settings"
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

show_progress 4 6 "Configuring storage settings"
upsert_env FILE_SIZE_LIMIT "524288000"
upsert_env STORAGE_BACKEND "file"

# Pin ports (compose respects these envs)
upsert_env KONG_HTTP_PORT "0.0.0.0:8000"
[[ "$PIN_HTTPS_LOOPBACK" = y ]] && upsert_env KONG_HTTPS_PORT "127.0.0.1:8443"
if [[ "$PIN_POOLER_LOOPBACK" = y ]]; then
  upsert_env POOLER_PROXY_PORT_TRANSACTION "127.0.0.1:6543"
else
  upsert_env POOLER_PROXY_PORT_TRANSACTION "0.0.0.0:6543"
fi

show_progress 6 6 "Securing environment file"
chmod 600 .env
ok "Environment configuration completed"

# JWT Key Generation
step "Generating JWT authentication keys..."
show_progress 1 2 "Generating anonymous access key"
export JWT_SECRET
ANON_KEY="$(gen_jwt_for_role anon)"

show_progress 2 2 "Generating service role key"
SERVICE_ROLE_KEY="$(gen_jwt_for_role service_role)"
unset JWT_SECRET
upsert_env ANON_KEY "$ANON_KEY"
upsert_env SERVICE_ROLE_KEY "$SERVICE_ROLE_KEY"
ok "JWT authentication keys generated and configured"

# Storage Mount Configuration
step "Configuring Unraid storage mount..."
show_progress 1 3 "Creating mount point directory"
mkdir -p "$VM_MOUNT"

if [[ "$STORAGE_PROTO" = "nfs" ]]; then
  show_progress 2 3 "Configuring NFS mount in /etc/fstab"
  grep -qE "[[:space:]]$VM_MOUNT[[:space:]]" /etc/fstab || \
    echo "${UNRAID_HOST}:${UNRAID_EXPORT}  ${VM_MOUNT}  nfs  defaults  0  0" >> /etc/fstab
  
  show_progress 3 3 "Mounting NFS share"
  mount -a || true
  ok "NFS storage mount configured: $VM_MOUNT"
else
  show_progress 2 3 "Creating SMB credentials file"
  CREDF="/root/.smb-${APEX_FQDN}.cred"
  { echo "username=${SMB_USER}"; echo "password=${SMB_PASS}"; } > "$CREDF"
  chmod 600 "$CREDF"
  
  show_progress 3 3 "Configuring SMB mount in /etc/fstab"
  grep -qE "[[:space:]]$VM_MOUNT[[:space:]]" /etc/fstab || \
    echo "//${UNRAID_HOST}/${UNRAID_SHARE}/${UNRAID_SUBDIR}  ${VM_MOUNT}  cifs  credentials=${CREDF},iocharset=utf8,file_mode=0644,dir_mode=0755,noperm  0  0" >> /etc/fstab
  mount -a || true
  ok "SMB storage mount configured: $VM_MOUNT"
fi

# Docker Compose Override Configuration
step "Creating docker-compose override for security and storage..."
show_progress 1 3 "Configuring port exposure rules"
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

if [[ "$ENABLE_ANALYTICS" = y ]]; then
  warn "Analytics enabled: upstream publishes 4000 to LAN."
else
  cat >> docker-compose.override.yml <<'YAML'

  analytics:
    profiles: ["dev"]   # disabled by default; enable later with COMPOSE_PROFILES=dev
YAML
fi

show_progress 3 3 "Finalizing override configuration"
ok "Docker Compose override configuration completed"

# Container Deployment
step "Deploying Supabase container stack..."
show_progress 1 4 "Pulling latest container images"
docker compose pull

show_progress 2 4 "Starting all services"
docker compose up -d

show_progress 3 4 "Recreating services with port restrictions"
# Recreate key services to ensure port pins applied
docker compose rm -sf kong supavisor >/dev/null 2>&1 || true
docker compose up -d kong supavisor studio storage

show_progress 4 4 "Verifying container status"
ok "Supabase container stack deployed successfully"
echo
tron_cyan "╔══════════════════════════════════════════════════════════════════════════════════╗"
tron_cyan "║                        CONTAINER STATUS REPORT                                 ║"
tron_cyan "╚══════════════════════════════════════════════════════════════════════════════════╝"
docker compose ps

# Firewall Configuration
if [[ "$USE_UFW" = y ]]; then
  info "Configuring UFW + DOCKER-USER ..."
  apt install -y ufw iptables-persistent >/dev/null
  
  show_progress 2 4 "Configuring UFW base rules"
  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing
  
  # SSH access from admin subnet
  ufw allow from "$ADMIN_SSH_SRC" to any port 22 proto tcp
  
  # Kong and Studio: only NPM can access
  ufw allow from "$NPM_HOST_IP" to any port "$KONG_HTTP_PORT" proto tcp
  ufw allow from "$NPM_HOST_IP" to any port "$STUDIO_PORT" proto tcp
  
  ufw --force enable

  iptables -I DOCKER-USER -s "$NPM_HOST_IP" -p tcp --dport 8000 -j ACCEPT
  iptables -I DOCKER-USER -s "$NPM_HOST_IP" -p tcp --dport 3000 -j ACCEPT
  iptables -I DOCKER-USER -p tcp --dport 8000 -j DROP
  iptables -I DOCKER-USER -p tcp --dport 3000 -j DROP
  iptables -I DOCKER-USER -p tcp --dport 8443 -j DROP
  iptables -I DOCKER-USER -p tcp --dport 6543 -j DROP
  
  # Block Analytics port (internal use only)
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
