#!/usr/bin/env bash
# ============================================================================
# WATTFOURCE SUPABASE INSTALLER (PHASE 2)
# 
# This script configures and deploys Supabase services.
# Prerequisites (Git, Docker, Docker Compose) must be installed first.
# 
# Installation is a two-phase process:
#   Phase 1: Run prerequisites-install.sh (installs Docker, Git, etc.)
#   Phase 2: Run this script (configures and deploys Supabase)
# ============================================================================
set -euo pipefail

# Get script directory for log file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGFILE="${SCRIPT_DIR}/supabase-install-$(date +%Y%m%d-%H%M%S).log"

# Color definitions
C_CYAN="\033[1;36m"
C_BLUE="\033[1;34m"
C_GREEN="\033[1;32m"
C_YELLOW="\033[1;33m"
C_RED="\033[1;31m"
C_MAGENTA="\033[1;35m"
C_WHITE="\033[1;37m"
C_RESET="\033[0m"

# Logging functions
log() { 
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE" >/dev/null
}

# Display functions
clear_screen() { clear; }

animate_light_cycle_intro() { :; }

print_header() {
    clear
    printf "${C_CYAN}WATTFOURCE${C_RESET} — Supabase Installation (Phase 2)\n"
    printf "Log: %s\n\n" "$LOGFILE"
}

print_step_header() {
    local step="$1"
    local title="$2"
    printf "\n${C_BLUE}-- %s: %s --${C_RESET}\n\n" "STEP $step" "$title"
}

print_info() {
    printf "${C_CYAN}◉${C_RESET} %s\n" "$1"
}

print_success() {
    printf "${C_GREEN}✓${C_RESET} %s\n" "$1"
}

print_warning() {
    printf "${C_YELLOW}⚠${C_RESET} %s\n" "$1"
}

print_error() {
    printf "${C_RED}✗${C_RESET} %s\n" "$1" >&2
}

print_config_line() {
    printf "  ${C_WHITE}%-30s${C_CYAN}%s${C_RESET}\n" "$1:" "$2"
}

ask() { 
    local p="$1" d="${2-}" v
    # Ensure output is flushed before reading
    printf "${C_MAGENTA}▶${C_RESET} ${C_WHITE}%s${C_RESET}" "$p" >&2
    [[ -n "$d" ]] && printf " ${C_CYAN}[%s]${C_RESET}" "$d" >&2
    printf ": " >&2
    read -r v </dev/tty
    echo "${v:-$d}"
}

ask_yn() {
  local p="$1" d="${2:-y}" a
  while true; do
        # Ensure output is flushed before reading
        printf "${C_MAGENTA}▶${C_RESET} ${C_WHITE}%s${C_RESET} ${C_CYAN}[" "$p" >&2
        [[ "$d" = "y" ]] && printf "Y/n" >&2 || printf "y/N" >&2
        printf "]${C_RESET}: " >&2
        read -r a </dev/tty || true
        a="${a:-$d}"
        case "$a" in
            y|Y) echo y; return;;
            n|N) echo n; return;;
            *) print_warning "Please enter y or n";;
        esac
  done
}

# Progress spinner
show_spinner() {
    local pid=$1
    local msg=$2
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    
    printf "${C_CYAN}⟳${C_RESET} %s " "$msg"
    
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) % 10 ))
        printf "\b${spin:$i:1}"
        sleep 0.1
    done
    
    wait "$pid"
    local status=$?
    
    if [ $status -eq 0 ]; then
        printf "\b${C_GREEN}✓${C_RESET}\n"
    else
        printf "\b${C_RED}✗${C_RESET}\n"
        print_error "Command failed. Check $LOGFILE for details."
        return $status
    fi
}

# Execute command silently with spinner
exec_with_spinner() {
    local msg="$1"
    shift
    log "Executing: $*"
    
    # Run command in background, capture exit status properly
    set +e  # Temporarily disable exit on error
    "$@" >> "$LOGFILE" 2>&1 &
    local bg_pid=$!
    show_spinner $bg_pid "$msg"
    local exit_code=$?
    set -e  # Re-enable exit on error
    
    if [ $exit_code -ne 0 ]; then
        print_error "Command failed with exit code $exit_code"
        print_error "Check log file for details: $LOGFILE"
        print_error "Last 10 lines of log:"
        tail -n 10 "$LOGFILE" >&2 || true
        return $exit_code
    fi
    
    return 0
}

# Validation functions
valid_domain() { [[ "$1" =~ ^[A-Za-z0-9.-]+$ ]] && [[ "$1" == *.* ]] && [[ "$1" != .* ]] && [[ "$1" != *..* ]]; }
ends_with_apex() { [[ "$1" == *".$2" ]]; }

# Utility functions
require_root() { 
    [[ ${EUID:-$(id -u)} -eq 0 ]] || { 
        print_error "This script must be run as root. Use: sudo -i"
        exit 1
    }
}

# Generate URL-safe base64 (no /, +, or = characters that break URLs)
gen_b64() { openssl rand -base64 "$1" 2>>"$LOGFILE" | tr '+/' '-_' | tr -d '='; }
# Generate standard base64 (for encryption keys that need standard base64 format)
gen_b64_standard() { openssl rand -base64 "$1" 2>>"$LOGFILE" | tr -d '\n'; }
b64url() { openssl enc -base64 -A | tr '+/' '-_' | tr -d '='; }

gen_jwt_for_role() {
  local role="$1" header payload hb pb sig iat exp
  iat=$(date +%s); exp=$((iat + 3600*24*365*5))
  header='{"typ":"JWT","alg":"HS256"}'
  payload="$(jq -nc --arg r "$role" --argjson i "$iat" --argjson e "$exp" \
        '{"role":$r,"iss":"supabase","iat":$i,"exp":$e}' 2>>"$LOGFILE")"
  hb="$(printf '%s' "$header" | b64url)"
  pb="$(printf '%s' "$payload" | b64url)"
    sig="$(printf '%s.%s' "$hb" "$pb" | openssl dgst -binary -sha256 -hmac "$JWT_SECRET" | b64url 2>>"$LOGFILE")"
  printf '%s.%s.%s\n' "$hb" "$pb" "$sig"
}

upsert_env() {
    local k="$1" v="$2"
    # All secrets are now URL-safe, so we can write them directly
    echo "${k}=${v}" >> .env
    log "Set env: $k"
}

# Auto-detect local IP
auto_detect_ip() {
    ip -4 addr show 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n1
}

#==============================================================================
# MAIN INSTALLATION FLOW
#==============================================================================

# Initialize log
log "=== WATTFOURCE Supabase Installation Started ==="
log "Script: $0"
log "User: $(whoami)"
log "Working Directory: $(pwd)"

require_root

clear_screen
print_header

LOCAL_IP=$(auto_detect_ip)
print_info "Auto-detected local IP: ${LOCAL_IP:-unable to detect}"
print_info "Log file: $LOGFILE"
echo

# STEP 1: Feature Selection
print_step_header "1" "FEATURE SELECTION"
echo

# Ensure terminal is ready for interactive input
stty sane 2>/dev/null || true

ENABLE_EMAIL=$(ask_yn "Enable Email Authentication?" "y")
ENABLE_PHONE=$(ask_yn "Enable Phone Authentication?" "y")
ENABLE_ANONYMOUS=$(ask_yn "Enable Anonymous Users?" "n")
ENABLE_STORAGE=$(ask_yn "Enable Storage (file uploads)?" "y")
ENABLE_REALTIME=$(ask_yn "Enable Realtime?" "y")
ENABLE_EDGE=$(ask_yn "Enable Edge Functions?" "y")

# Analytics is always enabled (required for Studio dashboard and monitoring)
# Most Supabase services depend on analytics: Studio, Kong, Auth, REST, Meta, Functions
# The 2GB RAM cost is worth it for full functionality and monitoring capabilities
ENABLE_ANALYTICS="y"

log "Feature selection: Email=$ENABLE_EMAIL Phone=$ENABLE_PHONE Anonymous=$ENABLE_ANONYMOUS Storage=$ENABLE_STORAGE Realtime=$ENABLE_REALTIME Edge=$ENABLE_EDGE Analytics=$ENABLE_ANALYTICS"

# STEP 2: Generating Secrets
print_step_header "2" "GENERATING SECRETS"
echo
print_info "Generating crypto-secure secrets..."

POSTGRES_PASSWORD="$(gen_b64 32)"
JWT_SECRET="$(gen_b64 48)"
# Encryption keys must use standard base64 (not URL-safe) for AES-GCM compatibility
PG_META_CRYPTO_KEY="$(gen_b64_standard 32)"
SECRET_KEY_BASE="$(gen_b64_standard 64)"
VAULT_ENC_KEY="$(gen_b64_standard 32)"
LOGFLARE_PUBLIC="$(gen_b64 32)"
LOGFLARE_PRIVATE="$(gen_b64 32)"
DASHBOARD_PASSWORD="$(gen_b64 16)"

log "Generated: POSTGRES_PASSWORD, JWT_SECRET, PG_META_CRYPTO_KEY, SECRET_KEY_BASE, VAULT_ENC_KEY, LOGFLARE_PUBLIC, LOGFLARE_PRIVATE, DASHBOARD_PASSWORD"
print_success "Secrets generated"

# STEP 3: Database Config
print_step_header "3" "DATABASE CONFIG"
echo
POSTGRES_HOST=$(ask "PostgreSQL Host" "db")
POSTGRES_DB=$(ask "PostgreSQL Database" "postgres")
# POSTGRES_PORT is handled internally by Docker Compose (always 5432 inside the network)

log "Database: host=$POSTGRES_HOST db=$POSTGRES_DB"

# STEP 4: API Gateway Config
print_step_header "4" "API GATEWAY CONFIG"
echo
KONG_HTTP_PORT=$(ask "Kong HTTP Port" "8000")
KONG_HTTPS_PORT=$(ask "Kong HTTPS Port" "8443")

log "Kong ports: HTTP=$KONG_HTTP_PORT HTTPS=$KONG_HTTPS_PORT"

# STEP 5: Application URLs
print_step_header "5" "APPLICATION URLS"
echo

# Get apex domain
while :; do
    APEX_FQDN=$(ask "Apex domain (REQUIRED, e.g. example.com)" "")
    if [[ -z "$APEX_FQDN" ]]; then
        print_warning "Apex domain is required"
        continue
    fi
    if valid_domain "$APEX_FQDN" && [[ "$APEX_FQDN" != *.*.*.* ]]; then
        break
    else
        print_warning "Enter a valid apex domain (e.g. example.com, not www.example.com)"
    fi
done

SITE_URL=$(ask "Frontend URL (SITE_URL)" "https://studio.${APEX_FQDN}")
API_URL=$(ask "Supabase API URL (API_EXTERNAL_URL)" "https://api.${APEX_FQDN}")
ADDITIONAL_REDIRECT=$(ask "Additional redirect URLs (comma-separated, optional)" "")

log "URLs: apex=$APEX_FQDN site=$SITE_URL api=$API_URL"

# STEP 6: Email Auth Config
print_step_header "6" "EMAIL AUTH CONFIG"
echo

if [[ "$ENABLE_EMAIL" = "y" ]]; then
    EMAIL_AUTOCONFIRM=$(ask_yn "Auto-confirm email signups? (dev only)" "n")
    ENABLE_SIGNUP=$(ask_yn "Use Resend for email delivery?" "y")
    
    if [[ "$ENABLE_SIGNUP" = "y" ]]; then
        print_info "Get your credentials from: https://resend.com/emails"
        RESEND_API_KEY=$(ask "Resend API Key" "")
        RESEND_SMTP_HOST=$(ask "Resend SMTP Host" "smtp.resend.com")
    else
        RESEND_API_KEY=""
        RESEND_SMTP_HOST="smtp.yourmail.tld"
    fi
else
    EMAIL_AUTOCONFIRM="false"
    ENABLE_SIGNUP="n"
    RESEND_API_KEY=""
    RESEND_SMTP_HOST="smtp.yourmail.tld"
fi

log "Email: autoconfirm=$EMAIL_AUTOCONFIRM smtp_host=$RESEND_SMTP_HOST"

# Phone Auth configuration (if enabled)
if [[ "$ENABLE_PHONE" = "y" ]]; then
    ENABLE_PHONE_AUTOCONFIRM=$(ask_yn "Auto-confirm phone signups? (dev only)" "n")
else
    ENABLE_PHONE_AUTOCONFIRM="false"
fi

# STEP 7: Studio Configuration
print_step_header "7" "STUDIO CONFIG"
echo

DASHBOARD_USERNAME=$(ask "Dashboard Username" "supabase")
STUDIO_DEFAULT_ORGANIZATION=$(ask "Studio Default Organization" "Default Organization")
STUDIO_DEFAULT_PROJECT=$(ask "Studio Default Project" "Default Project")

USE_OPENAI=$(ask_yn "Enable SQL Editor AI Assistant? (requires OpenAI API key)" "n")
if [[ "$USE_OPENAI" = "y" ]]; then
    OPENAI_API_KEY=$(ask "OpenAI API Key" "")
else
    OPENAI_API_KEY=""
fi

log "Studio: user=$DASHBOARD_USERNAME org=$STUDIO_DEFAULT_ORGANIZATION project=$STUDIO_DEFAULT_PROJECT"

# STEP 8: Additional Configuration
print_step_header "8" "ADDITIONAL CONFIG"
echo

JWT_EXPIRY=$(ask "JWT Expiry (seconds)" "3600")
PGRST_DB_SCHEMAS=$(ask "PostgREST DB Schemas" "public,storage,graphql_public")
POOLER_TENANT_ID=$(ask "Pooler Tenant ID" "supabase-local")

log "Config: jwt_expiry=$JWT_EXPIRY schemas=$PGRST_DB_SCHEMAS pooler_tenant=$POOLER_TENANT_ID"

# Storage configuration
if [[ "$ENABLE_STORAGE" = "y" ]]; then
    print_step_header "9" "STORAGE CONFIG"
    echo
    
    print_info "Storage architecture: Unraid share → VM mount point → Docker container"
    echo
    
    STORAGE_PROTO=$(ask "Storage protocol (nfs|smb)" "nfs")
    
if [[ "$STORAGE_PROTO" = "nfs" ]]; then
        UNRAID_HOST=$(ask "Unraid server hostname or IP (e.g. 192.168.1.70)" "")
        UNRAID_EXPORT=$(ask "Unraid NFS export path" "/mnt/user/supabase-storage/${APEX_FQDN}")
        STORAGE_MOUNT=$(ask "VM mount point" "/mnt/unraid/supabase-storage/${APEX_FQDN}")
        exec_with_spinner "Installing NFS client..." apt install -y nfs-common || {
            print_error "Failed to install NFS client"
            exit 1
        }
    else
        UNRAID_HOST=$(ask "Unraid server hostname or IP (e.g. 192.168.1.70)" "")
        UNRAID_SHARE=$(ask "Unraid SMB share name" "supabase-storage")
        # SMB mounts the entire share, then Docker uses a subfolder within it
        SMB_MOUNT_BASE="/mnt/unraid"
        STORAGE_MOUNT="${SMB_MOUNT_BASE}/${UNRAID_SHARE}/${APEX_FQDN}"
        SMB_USER=$(ask "SMB username (REQUIRED)" "")
        SMB_PASS=$(ask "SMB password (REQUIRED)" "")
        exec_with_spinner "Installing SMB client..." apt install -y cifs-utils || {
            print_error "Failed to install SMB client"
            exit 1
        }
    fi
    VM_MOUNT="$STORAGE_MOUNT"
    log "Storage: proto=$STORAGE_PROTO host=$UNRAID_HOST mount=$VM_MOUNT"
else
    VM_MOUNT=""
fi

# Network config - make all services accessible from network
PIN_HTTPS_LOOPBACK="n"
PIN_POOLER_LOOPBACK="n"

# Configuration Summary
clear_screen
print_header
print_step_header "✓" "CONFIGURATION SUMMARY"
echo

printf "${C_WHITE}Network Configuration:${C_RESET}\n"
print_config_line "Apex Domain" "$APEX_FQDN"
print_config_line "Frontend URL" "$SITE_URL"
print_config_line "API URL" "$API_URL"
echo

printf "${C_WHITE}Services:${C_RESET}\n"
print_config_line "Email Auth" "$ENABLE_EMAIL"
print_config_line "Phone Auth" "$ENABLE_PHONE"
print_config_line "Anonymous Users" "$ENABLE_ANONYMOUS"
print_config_line "Storage" "$ENABLE_STORAGE"
print_config_line "Realtime" "$ENABLE_REALTIME"
print_config_line "Edge Functions" "$ENABLE_EDGE"

printf "${C_WHITE}Core Services (Always Enabled):${C_RESET}\n"
print_config_line "Analytics/Logs" "Enabled (Studio dashboard & monitoring)"
echo

printf "${C_WHITE}Dashboard:${C_RESET}\n"
print_config_line "Username" "$DASHBOARD_USERNAME"
print_config_line "Organization" "$STUDIO_DEFAULT_ORGANIZATION"
print_config_line "Project" "$STUDIO_DEFAULT_PROJECT"
echo

if [[ "$ENABLE_STORAGE" = "y" ]]; then
    printf "${C_WHITE}Storage:${C_RESET}\n"
    print_config_line "Protocol" "$STORAGE_PROTO"
    print_config_line "Unraid Host" "$UNRAID_HOST"
    print_config_line "Mount Point" "$VM_MOUNT"
    echo
fi

printf "${C_WHITE}Network Access:${C_RESET}\n"
print_config_line "All Ports" "Network accessible (0.0.0.0)"
print_config_line "Kong HTTP" "0.0.0.0:${KONG_HTTP_PORT}"
print_config_line "Kong HTTPS" "0.0.0.0:${KONG_HTTPS_PORT}"
print_config_line "Supavisor Pooler" "0.0.0.0:6543"
print_config_line "Studio Dashboard" "0.0.0.0:3000"
echo

if [[ $(ask_yn "Proceed with installation?" "y") = "n" ]]; then
    print_warning "Installation aborted by user."
    log "Installation aborted by user"
    exit 1
fi

log "Configuration confirmed, proceeding with installation"

#==============================================================================
# INSTALLATION PHASE
#==============================================================================

clear_screen
print_header

# Verify prerequisites are installed
print_step_header "◉" "VERIFYING PREREQUISITES"
echo

print_info "Checking required tools..."

# Check for required commands
MISSING_DEPS=()
for cmd in curl gpg jq openssl git docker; do
    if ! command -v $cmd >/dev/null 2>&1; then
        MISSING_DEPS+=("$cmd")
        print_error "$cmd is not installed"
    else
        print_success "$cmd is available"
    fi
done

# Check for Docker Compose plugin
if ! docker compose version >/dev/null 2>&1; then
    MISSING_DEPS+=("docker-compose-plugin")
    print_error "Docker Compose plugin is not installed"
else
    print_success "Docker Compose is available"
fi

# If any dependencies are missing, provide helpful error message
if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
    echo
    print_error "Missing required prerequisites: ${MISSING_DEPS[*]}"
    echo
    printf "${C_YELLOW}Please run the prerequisites installer first:${C_RESET}\n"
    printf "${C_CYAN}sudo bash prerequisites-install.sh${C_RESET}\n"
    echo
    printf "${C_YELLOW}Or download and run it directly:${C_RESET}\n"
    printf "${C_CYAN}sudo bash -c 'cd /tmp && wget --no-cache -O prerequisites-install.sh https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/prerequisites-install.sh && chmod +x prerequisites-install.sh && ./prerequisites-install.sh'${C_RESET}\n"
    echo
    log "Installation aborted: missing prerequisites - ${MISSING_DEPS[*]}"
    exit 1
fi

print_success "All prerequisites verified"

# Check Docker service health
print_step_header "◉" "VERIFYING DOCKER SERVICE"
echo

if ! systemctl is-active --quiet docker; then
    print_warning "Docker service is not running"
    if [[ $(ask_yn "Start Docker service?" "y") = "y" ]]; then
        exec_with_spinner "Starting Docker service..." systemctl start docker || {
            print_error "Failed to start Docker service"
            exit 1
        }
        sleep 3
    else
        print_error "Docker service must be running"
        exit 1
    fi
fi

print_success "Docker service is healthy"

# Setup directory
print_step_header "◉" "SETTING UP DIRECTORY"
echo

ROOT="/srv/supabase"
exec_with_spinner "Creating deployment directory..." mkdir -p "$ROOT" || {
    print_error "Failed to create deployment directory"
    exit 1
}
cd "$ROOT" || {
    print_error "Failed to change to deployment directory"
    exit 1
}
log "Changed directory to $ROOT"

# Download Supabase
exec_with_spinner "Fetching Supabase docker bundle..." bash -c "
    set -euo pipefail
    git clone --depth 1 https://github.com/supabase/supabase /tmp/supabase || exit 1
    cp -rf /tmp/supabase/docker/* /srv/supabase/ || exit 1
    # Create a clean .env file
    touch /srv/supabase/.env || exit 1
    rm -rf /tmp/supabase || exit 1
" || {
    print_error "Failed to download Supabase bundle. Please check your internet connection."
    exit 1
}

# Generate JWT keys
print_step_header "◉" "GENERATING JWT KEYS"
echo

JWT_SECRET_ENV="$JWT_SECRET"
export JWT_SECRET
ANON_KEY="$(gen_jwt_for_role anon)"
SERVICE_ROLE_KEY="$(gen_jwt_for_role service_role)"
unset JWT_SECRET

log "Generated JWT keys"
print_success "JWT keys generated"

# Configure environment
print_step_header "◉" "CONFIGURING ENVIRONMENT"
echo

print_info "Writing environment variables..."

# URLs
upsert_env SUPABASE_PUBLIC_URL "$API_URL"
upsert_env SITE_URL "$SITE_URL"
upsert_env ADDITIONAL_REDIRECT_URLS "$ADDITIONAL_REDIRECT"

# Secrets
upsert_env POSTGRES_PASSWORD "$POSTGRES_PASSWORD"
upsert_env JWT_SECRET "$JWT_SECRET_ENV"
upsert_env ANON_KEY "$ANON_KEY"
upsert_env SERVICE_ROLE_KEY "$SERVICE_ROLE_KEY"
upsert_env DASHBOARD_USERNAME "$DASHBOARD_USERNAME"
upsert_env DASHBOARD_PASSWORD "$DASHBOARD_PASSWORD"
upsert_env SECRET_KEY_BASE "$SECRET_KEY_BASE"
upsert_env VAULT_ENC_KEY "$VAULT_ENC_KEY"
upsert_env PG_META_CRYPTO_KEY "$PG_META_CRYPTO_KEY"

# Database
upsert_env POSTGRES_HOST "$POSTGRES_HOST"
upsert_env POSTGRES_DB "$POSTGRES_DB"
upsert_env POSTGRES_PORT "5432"

# Supavisor - Connection Pooler
upsert_env POOLER_PROXY_PORT_TRANSACTION "6543"
upsert_env POOLER_DEFAULT_POOL_SIZE "20"
upsert_env POOLER_MAX_CLIENT_CONN "100"
upsert_env POOLER_TENANT_ID "$POOLER_TENANT_ID"
upsert_env POOLER_DB_POOL_SIZE "5"

# API Proxy - Kong
upsert_env KONG_HTTP_PORT "$KONG_HTTP_PORT"
upsert_env KONG_HTTPS_PORT "$KONG_HTTPS_PORT"

# API - PostgREST
upsert_env PGRST_DB_SCHEMAS "$PGRST_DB_SCHEMAS"

# Auth - GoTrue
upsert_env SITE_URL "$SITE_URL"
upsert_env ADDITIONAL_REDIRECT_URLS "$ADDITIONAL_REDIRECT"
upsert_env JWT_EXPIRY "$JWT_EXPIRY"
upsert_env DISABLE_SIGNUP "$([[ "$ENABLE_EMAIL" = "y" ]] && echo false || echo true)"
upsert_env API_EXTERNAL_URL "$API_URL"

# Mailer Config
upsert_env MAILER_URLPATHS_CONFIRMATION "/auth/v1/verify"
upsert_env MAILER_URLPATHS_INVITE "/auth/v1/verify"
upsert_env MAILER_URLPATHS_RECOVERY "/auth/v1/verify"
upsert_env MAILER_URLPATHS_EMAIL_CHANGE "/auth/v1/verify"

# Email auth
upsert_env ENABLE_EMAIL_SIGNUP "$([[ "$ENABLE_EMAIL" = "y" ]] && echo true || echo false)"
upsert_env ENABLE_EMAIL_AUTOCONFIRM "$([[ "$EMAIL_AUTOCONFIRM" = "y" ]] && echo true || echo false)"
upsert_env SMTP_ADMIN_EMAIL "$([[ "$ENABLE_EMAIL" = "y" ]] && echo "no-reply@$APEX_FQDN" || echo "admin@example.com")"
upsert_env SMTP_HOST "$RESEND_SMTP_HOST"
upsert_env SMTP_PORT "587"
upsert_env SMTP_USER "resend"
upsert_env SMTP_PASS "$RESEND_API_KEY"
upsert_env SMTP_SENDER_NAME "Supabase Auth"
upsert_env ENABLE_ANONYMOUS_USERS "$([[ "$ENABLE_ANONYMOUS" = "y" ]] && echo true || echo false)"

# Phone auth
upsert_env ENABLE_PHONE_SIGNUP "$([[ "$ENABLE_PHONE" = "y" ]] && echo true || echo false)"
upsert_env ENABLE_PHONE_AUTOCONFIRM "$([[ "$ENABLE_PHONE_AUTOCONFIRM" = "y" ]] && echo true || echo false)"

# Studio
upsert_env STUDIO_DEFAULT_ORGANIZATION "$STUDIO_DEFAULT_ORGANIZATION"
upsert_env STUDIO_DEFAULT_PROJECT "$STUDIO_DEFAULT_PROJECT"
upsert_env SUPABASE_PUBLIC_URL "$API_URL"
upsert_env IMGPROXY_ENABLE_WEBP_DETECTION "true"
upsert_env OPENAI_API_KEY "$OPENAI_API_KEY"

# Functions
upsert_env FUNCTIONS_VERIFY_JWT "$([[ "$ENABLE_EDGE" = "y" ]] && echo false || echo false)"

upsert_env DOCKER_SOCKET_LOCATION "/var/run/docker.sock"

# Set LOGFLARE tokens for analytics (always enabled)
upsert_env LOGFLARE_API_KEY "$LOGFLARE_PUBLIC"
upsert_env LOGFLARE_PUBLIC_ACCESS_TOKEN "$LOGFLARE_PUBLIC"
upsert_env LOGFLARE_PRIVATE_ACCESS_TOKEN "$LOGFLARE_PRIVATE"

# Storage
[[ "$ENABLE_STORAGE" = "y" ]] && upsert_env STORAGE_BACKEND "file" || upsert_env STORAGE_BACKEND "stub"
upsert_env FILE_SIZE_LIMIT "524288000"

chmod 600 .env
log "Environment file configured and secured"
print_success "Environment configured"

# Mount storage
if [[ "$ENABLE_STORAGE" = "y" ]]; then
    print_step_header "◉" "MOUNTING STORAGE"
    echo
    
if [[ "$STORAGE_PROTO" = "nfs" ]]; then
        exec_with_spinner "Creating mount point..." mkdir -p "$VM_MOUNT" || {
            print_error "Failed to create mount point"
            exit 1
        }
  grep -qE "[[:space:]]$VM_MOUNT[[:space:]]" /etc/fstab || \
    echo "${UNRAID_HOST}:${UNRAID_EXPORT}  ${VM_MOUNT}  nfs  defaults  0  0" >> /etc/fstab
        exec_with_spinner "Mounting NFS share..." mount -a || {
            print_error "Failed to mount NFS share. Check that NFS export exists on Unraid."
            exit 1
        }
else
        # SMB: mount the share to base directory, then create subfolder
        SMB_MOUNT_POINT="${SMB_MOUNT_BASE}/${UNRAID_SHARE}"
        mkdir -p "$SMB_MOUNT_POINT"
        
  CREDF="/root/.smb-${APEX_FQDN}.cred"
        {
            echo "username=${SMB_USER}"
            echo "password=${SMB_PASS}"
        } > "$CREDF"
  chmod 600 "$CREDF"
        
        # Mount the entire SMB share
        grep -qE "[[:space:]]$SMB_MOUNT_POINT[[:space:]]" /etc/fstab || \
            echo "//${UNRAID_HOST}/${UNRAID_SHARE}  ${SMB_MOUNT_POINT}  cifs  credentials=${CREDF},iocharset=utf8  0  0" >> /etc/fstab
        exec_with_spinner "Mounting SMB share..." mount -a || {
            print_error "Failed to mount SMB share. Check credentials and share name."
            exit 1
        }
        
        # Create the domain-specific subfolder
        mkdir -p "$VM_MOUNT"
    fi
    log "Storage mounted at $VM_MOUNT"
fi

# Create docker-compose override
print_info "Creating docker-compose override..."

# Create docker-compose override for feature configuration and security
cat > docker-compose.override.yml <<YAML
services:
YAML

# Expose Studio for LAN access (admin dashboard)
cat >> docker-compose.override.yml <<YAML
  studio:
    ports:
      - "0.0.0.0:3000:3000"
YAML

# Expose Supavisor pooler for direct database connections
cat >> docker-compose.override.yml <<YAML
  supavisor:
    ports:
      - "0.0.0.0:6543:6543"
YAML

# Kong port configuration (only override if using non-default ports)
if [[ "$KONG_HTTP_PORT" != "8000" ]] || [[ "$KONG_HTTPS_PORT" != "8443" ]]; then
    cat >> docker-compose.override.yml <<YAML
  kong:
    ports:
      - "${KONG_HTTP_PORT}:8000"
      - "${KONG_HTTPS_PORT}:8443"
YAML
fi

# Disable external access to sensitive services (always do this for security)
cat >> docker-compose.override.yml <<YAML
  db:
    ports: []
  auth:
    ports: []
  rest:
    ports: []
  realtime:
    ports: []
YAML

# Analytics is always enabled (required for Studio dashboard and monitoring)
# Vector service will use default configuration

if [[ "$ENABLE_STORAGE" = "y" ]]; then
    cat >> docker-compose.override.yml <<YAML
  storage:
    ports: []
    volumes:
      - ${VM_MOUNT}:/var/lib/storage
YAML
fi


log "Docker compose override created"
print_success "Override configured"

# Check for existing Supabase installation
print_step_header "◉" "CHECKING FOR EXISTING INSTALLATION"
echo

# Check for any Supabase containers (running, stopped, or created)
if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q '^supabase-'; then
    print_warning "Existing Supabase containers detected (from previous installation)"
    
    # Show what containers exist
    echo
    print_info "Found containers:"
    docker ps -a --filter "name=supabase-" --format "table {{.Names}}\t{{.Status}}" 2>/dev/null | head -n 15
    echo
    
    if [[ $(ask_yn "Stop and remove ALL existing Supabase containers?" "y") = "y" ]]; then
        # Force stop and remove all Supabase containers
        print_info "Stopping and removing containers..."
        
        # Try docker compose down first (clean method)
        if docker compose ps -q 2>/dev/null | grep -q .; then
            exec_with_spinner "Stopping via docker compose..." docker compose down 2>/dev/null || true
        fi
        
        # Force remove any remaining containers (nuclear option)
        SUPABASE_CONTAINERS=$(docker ps -a --filter "name=supabase-" -q 2>/dev/null || true)
        if [[ -n "$SUPABASE_CONTAINERS" ]]; then
            exec_with_spinner "Force removing remaining containers..." bash -c "docker rm -f $SUPABASE_CONTAINERS" || {
                print_error "Failed to remove containers"
                exit 1
            }
        fi
        
        # Clean up Docker networks (prevents stale iptables rules)
        print_info "Cleaning up Docker networks..."
        docker network prune -f >> "$LOGFILE" 2>&1 || true
        
        # Restart Docker daemon to clear stale port bindings
        print_warning "Docker networking cleanup required"
        if [[ $(ask_yn "Restart Docker service to clear port bindings?" "y") = "y" ]]; then
            exec_with_spinner "Restarting Docker service..." systemctl restart docker || {
                print_warning "Could not restart Docker automatically"
                print_info "Please run: sudo systemctl restart docker"
                print_info "Then re-run this installer"
                exit 1
            }
            # Wait for Docker to fully restart
            sleep 5
            print_success "Docker service restarted"
        else
            print_warning "Skipping Docker restart - you may encounter port binding issues"
            print_info "If installation fails, manually run: sudo systemctl restart docker"
        fi
        
        print_success "All existing containers removed"
    else
        print_error "Cannot proceed with existing containers present"
        echo
        print_info "To manually remove them, run:"
        printf "  ${C_CYAN}cd /srv/supabase && docker compose down${C_RESET}\n"
        printf "  ${C_CYAN}docker ps -a | grep supabase | awk '{print \$1}' | xargs docker rm -f${C_RESET}\n"
        echo
        exit 1
    fi
else
    print_success "No existing containers found"
fi

# Check port availability
print_info "Checking port availability..."
PORTS_IN_USE=()

# Check Kong HTTP port
if ss -ltn 2>/dev/null | grep -q ":${KONG_HTTP_PORT} "; then
    PORTS_IN_USE+=("${KONG_HTTP_PORT} (Kong HTTP)")
fi

# Check Kong HTTPS port (only if not pinned to localhost)
if [[ "$PIN_HTTPS_LOOPBACK" != "y" ]] && ss -ltn 2>/dev/null | grep -q ":${KONG_HTTPS_PORT} "; then
    PORTS_IN_USE+=("${KONG_HTTPS_PORT} (Kong HTTPS)")
fi

# Check Supavisor pooler port (only if not pinned to localhost)
if [[ "$PIN_POOLER_LOOPBACK" != "y" ]] && ss -ltn 2>/dev/null | grep -q ":6543 "; then
    PORTS_IN_USE+=("6543 (Supavisor)")
fi

# Check Studio port (always 3000)
if ss -ltn 2>/dev/null | grep -q ":3000 "; then
    PORTS_IN_USE+=("3000 (Studio)")
fi

if [[ ${#PORTS_IN_USE[@]} -gt 0 ]]; then
    print_warning "The following ports are already in use:"
    for port in "${PORTS_IN_USE[@]}"; do
        printf "  ${C_YELLOW}•${C_RESET} %s\n" "$port"
    done
    echo
    print_info "To find what's using these ports, run: sudo ss -lptn | grep ':<port>'"
    echo
    if [[ $(ask_yn "Continue anyway?" "n") = "n" ]]; then
        print_warning "Installation aborted due to port conflicts"
        log "Installation aborted: ports in use - ${PORTS_IN_USE[*]}"
        exit 1
    fi
else
    print_success "All required ports are available"
fi

# Download container images
print_step_header "◉" "DOWNLOADING CONTAINER IMAGES"
echo

print_info "This may take several minutes depending on your internet connection..."
exec_with_spinner "Pulling container images..." docker compose pull || {
    print_error "Failed to pull Docker images. Please check your internet connection."
    exit 1
}

log "All container images downloaded successfully"
print_success "All images downloaded"

# Start containers
print_step_header "◉" "STARTING SUPABASE SERVICES"
echo

# Try starting containers with retry logic (Docker networking can be flaky)
MAX_RETRIES=3
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    print_info "Starting containers (attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)..."
    
    set +e  # Don't exit on error
    docker compose up -d >> "$LOGFILE" 2>&1
    DOCKER_EXIT_CODE=$?
    set -e
    
    if [ $DOCKER_EXIT_CODE -eq 0 ]; then
        print_success "Containers started successfully"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            print_warning "Container startup failed, cleaning up..."
            
            # Clean up failed attempt
            docker compose down >> "$LOGFILE" 2>&1 || true
            docker network prune -f >> "$LOGFILE" 2>&1 || true
            
            print_info "Waiting 10 seconds before retry..."
            sleep 10
        else
            print_error "Failed to start Supabase services after $MAX_RETRIES attempts"
            echo
            print_info "This is usually caused by Docker networking issues. Try:"
            printf "  ${C_CYAN}1. sudo systemctl restart docker${C_RESET}\n"
            printf "  ${C_CYAN}2. cd /srv/supabase && sudo docker compose up -d${C_RESET}\n"
            echo
            print_info "Check logs with: cd /srv/supabase && docker compose logs"
            print_info "Check ports with: sudo ss -tulpn | grep -E ':(8000|8443|6543|3000)'"
            exit 1
        fi
    fi
done

# Wait for database to be healthy
print_info "Waiting for database to be ready..."
for i in {1..30}; do
    if docker compose ps db | grep -q "healthy"; then
        print_success "Database is healthy"
        break
    fi
    sleep 2
done

log "Containers deployed successfully"


# Completion
log "=== Installation completed successfully ==="

clear
printf "${C_GREEN}Deployment successful.${C_RESET}\n\n"

# Display critical credentials in a prominent warning box
printf "${C_RED}╔══════════════════════════════════════════════════════════════════════════════════╗${C_RESET}\n"
printf "${C_RED}║                       🔴 RECORD THESE CREDENTIALS NOW 🔴                        ║${C_RESET}\n"
printf "${C_RED}║              These will be stored in /srv/supabase/.env only!                   ║${C_RESET}\n"
printf "${C_RED}╠══════════════════════════════════════════════════════════════════════════════════╣${C_RESET}\n"
echo
printf "${C_WHITE}Dashboard Access:${C_RESET}\n"
printf "  URL:      ${C_CYAN}%s${C_RESET}\n" "$API_URL"
printf "  Username: ${C_YELLOW}%s${C_RESET}\n" "$DASHBOARD_USERNAME"
printf "  Password: ${C_YELLOW}%s${C_RESET}\n" "$DASHBOARD_PASSWORD"
echo
printf "${C_WHITE}Database Access:${C_RESET}\n"
printf "  Host:     ${C_CYAN}%s${C_RESET}\n" "$POSTGRES_HOST"
printf "  Port:     ${C_CYAN}5432${C_RESET} (session) / ${C_CYAN}6543${C_RESET} (pooled)\n"
printf "  Database: ${C_CYAN}%s${C_RESET}\n" "$POSTGRES_DB"
printf "  Password: ${C_YELLOW}%s${C_RESET}\n" "$POSTGRES_PASSWORD"
printf "  Tenant:   ${C_CYAN}%s${C_RESET}\n" "$POOLER_TENANT_ID"
echo
printf "${C_WHITE}API Keys:${C_RESET}\n"
printf "${C_GREEN}ANON_KEY${C_RESET} (public - safe for frontend):\n"
printf "${C_YELLOW}%s${C_RESET}\n\n" "$ANON_KEY"
printf "${C_RED}SERVICE_ROLE_KEY${C_RESET} (secret - NEVER expose to frontend):\n"
printf "${C_YELLOW}%s${C_RESET}\n" "$SERVICE_ROLE_KEY"
echo
printf "${C_RED}╚══════════════════════════════════════════════════════════════════════════════════╝${C_RESET}\n\n"

printf "${C_WHITE}Access Your Supabase Instance:${C_RESET}\n"
print_config_line "Studio Dashboard" "$SITE_URL"
print_config_line "API Endpoint" "$API_URL"
print_config_line "VM IP Address" "$LOCAL_IP"
echo

printf "${C_WHITE}Next Steps:${C_RESET}\n"
echo "  1) Configure reverse proxy (optional) for SSL termination:"
echo "     • $API_URL → http://${LOCAL_IP}:${KONG_HTTP_PORT} (enable WebSockets)"
echo "     • $SITE_URL → http://${LOCAL_IP}:3000"
echo "  2) Or access directly:"
echo "     • Studio Dashboard: http://${LOCAL_IP}:3000"
echo "     • API Gateway: http://${LOCAL_IP}:${KONG_HTTP_PORT}"
echo "     • Database Pooler: postgresql://postgres.${POOLER_TENANT_ID}:${POSTGRES_PASSWORD}@${LOCAL_IP}:6543/postgres"
echo "  3) Test your API endpoint and visit Studio dashboard"
echo

printf "${C_CYAN}Installation log: ${C_WHITE}$LOGFILE${C_RESET}\n"
printf "${C_GREEN}✓ Supabase stack is up. Studio: $SITE_URL  API: $API_URL${C_RESET}\n\n"
