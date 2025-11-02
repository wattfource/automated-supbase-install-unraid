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

# Secret Generation Functions
# Following best practices for self-hosted Supabase:
# ALL secrets use Base64URL encoding (A-Za-z0-9-_ only, no padding)
# This provides:
# - URL safety: No special characters that break URLs or connection strings
# - Consistency: Same encoding for all secrets across the stack
# - Compatibility: Works with Supabase's crypto libraries (Erlang, Node.js)
# - Security: 256-bit minimum entropy for encryption keys

# Generate Base64URL (no padding): A-Za-z0-9-_ only, ~256-bit entropy for 32 bytes
gen_b64_url() { openssl rand "$1" 2>>"$LOGFILE" | base64 | tr '+/' '-_' | tr -d '=' | tr -d '\n'; }

# Generate fixed-length secret (for Supavisor/Cloak encryption keys)
# These need to be exactly N characters long (not N bytes encoded)
gen_fixed_secret() { 
    local len="$1"
    openssl rand -base64 48 2>>"$LOGFILE" | tr -d "=+/\n" | head -c "$len"
}

# Helper for JWT generation (URL-safe)
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
    # Secrets use either Base64URL (A-Za-z0-9-_) or Standard Base64 (A-Za-z0-9+/)
    # Both are safe to write directly to .env without quoting (no special shell characters)
    if grep -q "^${k}=" .env 2>/dev/null; then
        sed -i "s|^${k}=.*|${k}=${v}|" .env
    else
        echo "${k}=${v}" >> .env
    fi
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

# Phone Authentication Configuration
print_info "ℹ️  Phone Authentication uses SMS-based one-time passwords (OTP)"
echo "When phone auth is enabled:"
echo "  • Users can sign up/login using their phone number"
echo "  • Supabase sends OTP codes via SMS (requires SMS provider setup)"
echo "  • Supported providers: Twilio, Vonage, MessageBird, Textlocal"
echo "  • You'll need to configure SMS credentials in update-supabase.sh later"
echo "  • Note: Phone auth works but requires external SMS service (costs apply)"
echo

ENABLE_PHONE=$(ask_yn "Enable Phone Authentication?" "n")
ENABLE_ANONYMOUS=$(ask_yn "Enable Anonymous Users?" "n")
ENABLE_STORAGE=$(ask_yn "Enable Storage (file uploads)?" "y")
ENABLE_REALTIME=$(ask_yn "Enable Realtime?" "n")
ENABLE_EDGE=$(ask_yn "Enable Edge Functions?" "y")

# Analytics is always enabled (required for Studio dashboard and monitoring)
# Most Supabase services depend on analytics: Studio, Kong, Auth, REST, Meta, Functions
# The 2GB RAM cost is worth it for full functionality and monitoring capabilities
ENABLE_ANALYTICS="y"

# Studio dashboard access configuration
echo
print_info "Studio Dashboard Configuration"
print_warning "⚠️  Security Note:"
echo "  Studio is your admin dashboard with full database access"
echo "  Default: Accessible only via reverse proxy (recommended secure method)"
echo "  LAN Option: Open port 3000 on local network (less secure but convenient)"
echo
EXPOSE_STUDIO_LAN=$(ask_yn "Open Studio on port 3000 for LAN-only access?" "n")

log "Feature selection: Email=$ENABLE_EMAIL Phone=$ENABLE_PHONE Anonymous=$ENABLE_ANONYMOUS Storage=$ENABLE_STORAGE Realtime=$ENABLE_REALTIME Edge=$ENABLE_EDGE Analytics=$ENABLE_ANALYTICS StudioLAN=$EXPOSE_STUDIO_LAN"

# STEP 2: Generating Secrets
print_step_header "2" "GENERATING SECRETS"
echo
print_info "Generating crypto-secure secrets..."
print_info "Using URL-safe Base64 encoding (A-Za-z0-9-_) for all secrets"
print_info "This ensures compatibility across all Supabase services"
echo

# Generate secrets with proper formats for each service
# JWT signing: 64 chars of high-entropy base64url
JWT_SECRET="$(gen_b64_url 48)"
# Database password: 43 chars base64url
POSTGRES_PASSWORD="$(gen_b64_url 32)"
# Encryption keys for Supavisor/Cloak: MUST be exactly 32 characters (not 32 bytes encoded)
# These are used directly as AES-256 keys and must be exactly 32 ASCII chars
VAULT_ENC_KEY="$(gen_fixed_secret 32)"
PG_META_CRYPTO_KEY="$(gen_fixed_secret 32)"
# Session secret: 86 chars base64url
SECRET_KEY_BASE="$(gen_b64_url 64)"
# Analytics tokens: 43 chars base64url each
LOGFLARE_PUBLIC="$(gen_b64_url 32)"
LOGFLARE_PRIVATE="$(gen_b64_url 32)"
# Dashboard password: 22 chars base64url
DASHBOARD_PASSWORD="$(gen_b64_url 16)"

log "Generated secrets: JWT_SECRET, POSTGRES_PASSWORD, VAULT_ENC_KEY(32chars), PG_META_CRYPTO_KEY(32chars), SECRET_KEY_BASE, LOGFLARE tokens, DASHBOARD_PASSWORD"
print_success "All secrets generated with proper encoding for each service"

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
# Kong ports are fixed at defaults (no need to customize)
KONG_HTTP_PORT="8000"
KONG_HTTPS_PORT="8443"
print_info "Kong HTTP Port: ${KONG_HTTP_PORT}"
print_info "Kong HTTPS Port: ${KONG_HTTPS_PORT}"

log "Kong ports: HTTP=$KONG_HTTP_PORT HTTPS=$KONG_HTTPS_PORT"

# STEP 5: Application URLs & Email Auth Configuration  
print_step_header "5" "APPLICATION URLS & EMAIL AUTH"
echo

print_info "⚠️  Email Authentication Redirect Configuration"
echo "When users verify their email, they'll be redirected to your application."
echo "This must match your actual website domain."
echo

# Get apex domain  
while :; do
    APEX_FQDN=$(ask "Your domain (e.g. example.com, NOT www.example.com)" "")
    if [[ -z "$APEX_FQDN" ]]; then
        print_warning "Domain is required"
        continue
    fi
    if valid_domain "$APEX_FQDN" && [[ "$APEX_FQDN" != *.*.*.* ]]; then
        break
    else
        print_warning "Enter a valid domain (e.g. example.com)"
    fi
done

echo

print_info "Website URL Configuration"
USE_WWW=$(ask_yn "Will your website be served at www.${APEX_FQDN}?" "y")

# Build primary Site URL based on www preference
if [[ "$USE_WWW" = "y" ]]; then
    SITE_URL="https://www.${APEX_FQDN}"
else
    SITE_URL="https://${APEX_FQDN}"
fi

echo

print_info "Additional Subdomains for Authentication (optional)"
echo "Examples: api.${APEX_FQDN}, dashboard.${APEX_FQDN}, admin.${APEX_FQDN}"
ADDITIONAL_SUBDOMAINS=$(ask "Comma-separated list (or leave blank)" "")

# Build additional redirect URLs
ADDITIONAL_REDIRECT=""
if [[ -n "$ADDITIONAL_SUBDOMAINS" ]]; then
    ADDITIONAL_REDIRECT="$ADDITIONAL_SUBDOMAINS"
fi

# API endpoint
API_URL=$(ask "Supabase API URL" "https://api.${APEX_FQDN}")

echo
print_success "✓ Authentication URLs Configured:"
print_config_line "Primary Site URL (SITE_URL)" "$SITE_URL"
print_config_line "API URL (API_EXTERNAL_URL)" "$API_URL"
if [[ -n "$ADDITIONAL_REDIRECT" ]]; then
    print_config_line "Additional Redirect URLs" "$ADDITIONAL_REDIRECT"
fi
echo
print_info "ℹ️  URL Reference:"
echo "  • SITE_URL: Primary URL where your frontend is served (used for email redirects)"
echo "  • API_EXTERNAL_URL: Public API gateway URL (clients connect here)"
echo "  • SUPABASE_PUBLIC_URL: Studio internal URL (set equal to API_EXTERNAL_URL)"
echo

log "URLs: apex=$APEX_FQDN site=$SITE_URL api=$API_URL additional=$ADDITIONAL_REDIRECT"

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
    
    print_info "📱 Twilio SMS Provider Setup"
    echo "To use phone authentication, you need a Twilio account:"
    echo "  1. Sign up at: https://www.twilio.com"
    echo "  2. Find your Account SID and Auth Token in Twilio Console"
    echo "  3. Get a Twilio phone number for sending SMS"
    echo
    
    TWILIO_ACCOUNT_SID=$(ask "Twilio Account SID (leave blank to skip)" "")
    if [[ -n "$TWILIO_ACCOUNT_SID" ]]; then
        TWILIO_AUTH_TOKEN=$(ask "Twilio Auth Token" "")
        TWILIO_PHONE_NUMBER=$(ask "Twilio Phone Number (e.g., +1234567890)" "")
    else
        TWILIO_ACCOUNT_SID=""
        TWILIO_AUTH_TOKEN=""
        TWILIO_PHONE_NUMBER=""
        print_warning "Skipping Twilio setup - you can configure it later in update-supabase.sh"
    fi
else
    ENABLE_PHONE_AUTOCONFIRM="false"
    TWILIO_ACCOUNT_SID=""
    TWILIO_AUTH_TOKEN=""
    TWILIO_PHONE_NUMBER=""
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
    
    print_info "Storage architecture: PCI-based mount (configure via Unraid VM editor)"
    print_info "Mount point will be configured manually via Unraid VM editor"
    echo
    
    # Prompt for custom storage path segment
    STORAGE_CUSTOM=$(ask "Storage path segment (custom identifier)" "${STUDIO_DEFAULT_ORGANIZATION:-storage}")
    
    # Default mount point path for placeholder (user will configure via Unraid VM editor)
    VM_MOUNT="/mnt/user/supabase-storage/${STORAGE_CUSTOM}/${APEX_FQDN}"
    log "Storage: mount placeholder=$VM_MOUNT (configure via Unraid VM editor)"
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
    print_config_line "Status" "Enabled (PCI-based mount - configure via Unraid VM editor)"
    echo
fi

if [[ "$ENABLE_PHONE" = "y" ]] && [[ -n "$TWILIO_ACCOUNT_SID" ]]; then
    printf "${C_WHITE}Twilio SMS Configuration:${C_RESET}\n"
    print_config_line "Account SID" "${TWILIO_ACCOUNT_SID:0:10}..."
    print_config_line "Phone Number" "$TWILIO_PHONE_NUMBER"
    echo
fi

if [[ "$EXPOSE_STUDIO_LAN" = "y" ]]; then
    printf "${C_WHITE}Studio Dashboard:${C_RESET}
"
    print_config_line "LAN Access" "127.0.0.1:3000"
    echo
else
    printf "${C_WHITE}Studio Dashboard:${C_RESET}
"
    print_config_line "LAN Access" "Disabled (reverse proxy only)"
    echo
fi

printf "${C_WHITE}Network Access:${C_RESET}\n"
print_config_line "All Ports" "Network accessible (0.0.0.0)"
print_config_line "Kong HTTP" "0.0.0.0:${KONG_HTTP_PORT}"
print_config_line "Kong HTTPS" "0.0.0.0:${KONG_HTTPS_PORT}"
print_config_line "Supavisor Pooler" "0.0.0.0:6543"
# Studio Dashboard is internal-only (not exposed publicly)
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
upsert_env API_EXTERNAL_URL "$API_URL"
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

# Twilio SMS Provider (if configured)
if [[ -n "$TWILIO_ACCOUNT_SID" ]]; then
    upsert_env TWILIO_ACCOUNT_SID "$TWILIO_ACCOUNT_SID"
    upsert_env TWILIO_AUTH_TOKEN "$TWILIO_AUTH_TOKEN"
    upsert_env TWILIO_PHONE_NUMBER "$TWILIO_PHONE_NUMBER"
    log "Twilio SMS credentials configured"
fi

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

# Add fstab placeholder for PCI-based mount (if storage enabled)
if [[ "$ENABLE_STORAGE" = "y" ]]; then
    print_step_header "◉" "STORAGE MOUNT CONFIGURATION"
    echo
    
    print_info "Adding fstab placeholder for PCI-based mount..."

    # Add commented placeholder to fstab if it doesn't already exist
    if ! grep -q "# PCI-based mount for Supabase storage" /etc/fstab 2>/dev/null; then
        echo "" >> /etc/fstab
        echo "# PCI-based mount for Supabase storage - configure via Unraid VM editor" >> /etc/fstab
        echo "# Set mount tag to 'unraid' in Unraid VM editor - it will automatically mount to /mnt/user" >> /etc/fstab
        echo "# No fstab entry needed - Unraid VM editor handles the mount automatically" >> /etc/fstab
        log "Added fstab placeholder for PCI-based mount (unraid tag -> /mnt/user)"
        print_success "fstab placeholder added"
    else
        print_success "fstab placeholder already exists"
    fi

    print_info "Configure PCI passthrough in Unraid VM editor with mount tag 'unraid' (auto-mounts to /mnt/user)"
fi

# Create docker-compose.override.yml for Unraid-specific configuration
print_info "Creating docker-compose.override.yml..."

# Determine port bindings based on pinning preferences
if [[ "$PIN_HTTPS_LOOPBACK" = "y" ]]; then
    KONG_HTTPS_BIND="127.0.0.1:${KONG_HTTPS_PORT}:8443"
else
    KONG_HTTPS_BIND="0.0.0.0:${KONG_HTTPS_PORT}:8443"
fi

# Kong HTTP port binding (always network accessible for proxying)
KONG_HTTP_BIND="${KONG_HTTP_PORT}:8000"

if [[ "$PIN_POOLER_LOOPBACK" = "y" ]]; then
    POOLER_BIND="127.0.0.1:6543:6543"
else
    POOLER_BIND="0.0.0.0:6543:6543"
fi

cat > docker-compose.override.yml <<YAML
# UNRAID-specific configuration
# Overrides for $APEX_FQDN deployment

services:
  # Port security configuration
  kong:
    ports:
      - "${KONG_HTTP_BIND}"
      - "${KONG_HTTPS_BIND}"

  studio:
    ports:
      - "3000:3000"

  supavisor:
    ports:
      - "${POOLER_BIND}"

  # Disable external access to sensitive services
  db:
    ports: []
  auth:
    ports: []
  rest:
    ports: []
  realtime:
    ports: []

  # PCI-based mount for Supabase storage - configure via Unraid VM editor
  # Set mount tag to 'unraid' in Unraid VM editor (auto-mounts to /mnt/user)
  # After configuring PCI passthrough, uncomment the storage section below:
  # storage:
  #   ports: []
  #   volumes:
  #     - ${VM_MOUNT}:/var/lib/storage
  #   environment:
  #     - STORAGE_TENANT_ID=${APEX_FQDN}
  #     - STORAGE_S3_REGION=local
  #     - STORAGE_S3_BUCKET=unraid
  # Note: These environment variables replace the "stub" backend for self-hosted deployments
YAML

# Conditionally expose Studio on LAN
if [[ "$EXPOSE_STUDIO_LAN" = "y" ]]; then
    print_warning "⚠️  Studio will be accessible on port 3000 (LAN only)"
    cat >> docker-compose.override.yml <<YAML
  studio:
    ports:
      - "127.0.0.1:3000:3000"

YAML
else
    print_info "Studio accessible only via reverse proxy (no port exposed)"
fi

if [[ "$ENABLE_STORAGE" = "y" ]]; then
    # Note: Storage volume mount is commented out above
    # User must configure PCI passthrough via Unraid VM editor, then uncomment the storage section
    log "Storage enabled - PCI mount placeholder added to docker-compose.override.yml"
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

# Create helper scripts
print_step_header "◉" "CREATING HELPER SCRIPTS"
echo

HELPER_DIR="/srv/supabase/scripts"
mkdir -p "$HELPER_DIR"

print_info "Creating comprehensive diagnostic script..."
cat > "${HELPER_DIR}/diagnostic.sh" << 'DIAGNOSTIC_EOF'
#!/bin/bash
# Comprehensive Supabase Diagnostic Script
# Captures everything needed for troubleshooting

cd /srv/supabase 2>/dev/null || { echo "Error: /srv/supabase not found"; exit 1; }

echo "════════════════════════════════════════════════════════════════════════════"
echo "SUPABASE COMPREHENSIVE DIAGNOSTIC REPORT"
echo "Generated: $(date)"
echo "Hostname: $(hostname)"
echo "User: $(whoami)"
echo "════════════════════════════════════════════════════════════════════════════"
echo ""

# System Information
echo "=== SYSTEM INFORMATION ==="
echo "OS: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2)"
echo "Kernel: $(uname -r)"
echo "Uptime: $(uptime -p 2>/dev/null || uptime)"
echo "CPU: $(grep -m1 'model name' /proc/cpuinfo | cut -d':' -f2 | xargs)"
echo "CPU Cores: $(nproc)"
echo "Total RAM: $(free -h | grep Mem | awk '{print $2}')"
echo "Available RAM: $(free -h | grep Mem | awk '{print $7}')"
df -h / | tail -1 | awk '{print "Root Disk: " $2 " total, " $4 " available (" $5 " used)"}'
echo ""

# Docker Information
echo "=== DOCKER INFORMATION ==="
echo "Docker Version: $(docker --version 2>/dev/null || echo 'Not installed')"
echo "Docker Compose Version: $(docker compose version 2>/dev/null || echo 'Not installed')"
echo "Docker Status: $(systemctl is-active docker 2>/dev/null || echo 'Unknown')"
echo "Docker Root Dir: $(docker info 2>/dev/null | grep 'Docker Root Dir' | cut -d':' -f2 | xargs)"
echo ""
echo "Docker Disk Usage:"
docker system df 2>/dev/null || echo "Unable to get Docker disk usage"
echo ""

# Network Information
echo "=== NETWORK INFORMATION ==="
echo "IP Addresses:"
ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | awk '{print "  " $1}'
echo ""
echo "DNS Servers:"
grep nameserver /etc/resolv.conf 2>/dev/null | awk '{print "  " $2}' || echo "  Unable to read"
echo ""
echo "Active Listening Ports (Docker-related):"
sudo ss -tulpn 2>/dev/null | grep -E "(docker|:3000|:8000|:8443|:6543|:4000)" | head -20 || echo "Unable to check ports"
echo ""

# Container Status
echo "=== CONTAINER STATUS ==="
sudo docker compose ps
echo ""

echo "=== PORT BINDINGS (Detailed) ==="
sudo docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
echo ""

echo "=== CONTAINER RESTART COUNTS ==="
for container in $(sudo docker compose ps -q 2>/dev/null); do
    name=$(sudo docker inspect --format='{{.Name}}' $container | sed 's/\///')
    restarts=$(sudo docker inspect --format='{{.RestartCount}}' $container)
    echo "  $name: $restarts restarts"
done
echo ""

# Configuration Files
echo "=== DOCKER COMPOSE FILES ==="
echo "--- docker-compose.yml (first 50 lines) ---"
head -50 docker-compose.yml 2>/dev/null || echo "File not found"
echo ""
echo "--- docker-compose.override.yml ---"
cat docker-compose.override.yml 2>/dev/null || echo "File not found"
echo ""

# Environment Variables (sanitized)
echo "=== ENVIRONMENT VARIABLES (sanitized) ==="
echo "Checking critical .env variables..."
for var in POSTGRES_HOST POSTGRES_DB POSTGRES_PORT KONG_HTTP_PORT KONG_HTTPS_PORT \
           SITE_URL API_EXTERNAL_URL SUPABASE_PUBLIC_URL \
           ENABLE_EMAIL_SIGNUP ENABLE_PHONE_SIGNUP ENABLE_ANONYMOUS_USERS \
           JWT_SECRET POSTGRES_PASSWORD VAULT_ENC_KEY SECRET_KEY_BASE PG_META_CRYPTO_KEY \
           ANON_KEY SERVICE_ROLE_KEY DASHBOARD_USERNAME; do
    if sudo grep -q "^${var}=" .env 2>/dev/null; then
        value=$(sudo grep "^${var}=" .env | cut -d= -f2)
        length=${#value}
        # Check for sensitive variables
        case "$var" in
            *PASSWORD|*KEY|*SECRET|*TOKEN)
                # Check encoding format
                if echo "$value" | grep -q "[-_]"; then
                    format="URL-safe base64"
                elif echo "$value" | grep -q "[+/]"; then
                    format="Standard base64"
                elif echo "$value" | grep -q "^ey"; then
                    format="JWT token"
                else
                    format="Unknown"
                fi
                echo "  ✓ $var: [REDACTED] (${length} chars, ${format})"
                ;;
            *)
                echo "  ✓ $var: $value"
                ;;
        esac
    else
        echo "  ✗ $var: MISSING"
    fi
done
echo ""

# Volume Mounts
echo "=== VOLUME MOUNTS ==="
echo "Docker Volumes:"
sudo docker volume ls | grep supabase || echo "No supabase volumes found"
echo ""
echo "Storage Mount (if configured):"
mount | grep supabase || echo "No supabase mounts found"
echo ""
if [ -d "/mnt/unraid" ]; then
    echo "Unraid Mounts:"
    ls -lah /mnt/unraid/ 2>/dev/null || echo "Unable to list /mnt/unraid"
fi
echo ""

# Health Checks
echo "=== DETAILED HEALTH STATUS ==="
for service in db kong auth rest storage meta studio analytics realtime supavisor vector imgproxy functions; do
    container="supabase-${service}"
    if [ "$service" = "realtime" ]; then
        container="realtime-dev.supabase-realtime"
    elif [ "$service" = "functions" ]; then
        container="supabase-edge-functions"
    elif [ "$service" = "supavisor" ]; then
        container="supabase-pooler"
    fi
    
    if sudo docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^${container}$"; then
        status=$(sudo docker inspect --format='{{.State.Status}}' $container 2>/dev/null)
        health=$(sudo docker inspect --format='{{.State.Health.Status}}' $container 2>/dev/null || echo "N/A")
        started=$(sudo docker inspect --format='{{.State.StartedAt}}' $container 2>/dev/null)
        echo "[$service]"
        echo "  Status: $status"
        echo "  Health: $health"
        echo "  Started: $started"
    else
        echo "[$service] Container not found"
    fi
done
echo ""

# Service Connectivity Tests
echo "=== SERVICE CONNECTIVITY TESTS ==="
echo "Testing internal service connectivity..."
echo -n "Studio (port 3000): "
studio_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 2>/dev/null || echo "000")
if [ "$studio_code" != "000" ] && [ "$studio_code" != "" ]; then
    echo "✓ Accessible (HTTP $studio_code)"
else
    echo "✗ Not accessible"
fi

echo -n "Kong HTTP (port 8000): "
kong_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000 2>/dev/null || echo "000")
if [ "$kong_code" != "000" ] && [ "$kong_code" != "" ]; then
    echo "✓ Accessible (HTTP $kong_code)"
else
    echo "✗ Not accessible"
fi

echo -n "Kong HTTPS (port 8443): "
kong_https_code=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost:8443 2>/dev/null || echo "000")
if [ "$kong_https_code" != "000" ] && [ "$kong_https_code" != "" ]; then
    echo "✓ Accessible (HTTP $kong_https_code)"
else
    echo "✗ Not accessible"
fi

echo -n "Analytics (port 4000): "
analytics_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:4000 2>/dev/null || echo "000")
if [ "$analytics_code" != "000" ] && [ "$analytics_code" != "" ]; then
    echo "✓ Accessible (HTTP $analytics_code)"
else
    echo "✗ Not accessible"
fi

echo -n "PostgreSQL (port 5432): "
if sudo docker compose exec -T db pg_isready -U postgres >/dev/null 2>&1; then
    echo "✓ Accepting connections"
else
    echo "✗ Not accepting connections"
fi
echo ""

# Database Checks
echo "=== DATABASE CHECKS ==="
if sudo docker compose exec -T db psql -U postgres -d postgres -c "SELECT version();" >/dev/null 2>&1; then
    echo "✓ Database is responsive"
    echo ""
    echo "PostgreSQL Version:"
    sudo docker compose exec -T db psql -U postgres -d postgres -c "SELECT version();" 2>/dev/null | grep PostgreSQL
    echo ""
    echo "Database Size:"
    sudo docker compose exec -T db psql -U postgres -d postgres -c "SELECT pg_size_pretty(pg_database_size('postgres')) as size;" 2>/dev/null | tail -2
    echo ""
    echo "Schema Summary:"
    sudo docker compose exec -T db psql -U postgres -d postgres -c "SELECT schemaname, COUNT(*) as tables FROM pg_tables GROUP BY schemaname ORDER BY tables DESC;" 2>/dev/null | head -15
    echo ""
    echo "Active Connections:"
    sudo docker compose exec -T db psql -U postgres -d postgres -c "SELECT count(*) as active_connections FROM pg_stat_activity WHERE state = 'active';" 2>/dev/null | tail -2
    echo ""
    echo "Recent Supabase Migrations:"
    sudo docker compose exec -T db psql -U postgres -d postgres -c "SELECT version, inserted_at FROM supabase_migrations.schema_migrations ORDER BY inserted_at DESC LIMIT 5;" 2>/dev/null || echo "Migration table not found"
else
    echo "✗ Database is not responsive"
fi
echo ""

# Critical Service Logs
echo "=== SERVICE LOGS (last 30 lines each) ==="

echo "--- SUPAVISOR (Pooler) ---"
sudo docker compose ps supavisor 2>/dev/null
sudo docker logs supabase-pooler --tail 30 2>&1
echo ""

echo "--- KONG (API Gateway) ---"
sudo docker logs supabase-kong --tail 30 2>&1 | grep -E "(error|ERROR|warn|WARN|started|upstream)" || sudo docker logs supabase-kong --tail 15 2>&1
echo ""

echo "--- AUTH (GoTrue) ---"
sudo docker logs supabase-auth --tail 30 2>&1 | grep -E "(error|ERROR|warn|WARN|started|migration)" || sudo docker logs supabase-auth --tail 15 2>&1
echo ""

echo "--- STORAGE ---"
sudo docker logs supabase-storage --tail 20 2>&1 | grep -E "(error|ERROR|warn|WARN|started)" || sudo docker logs supabase-storage --tail 10 2>&1
echo ""

echo "--- REALTIME ---"
sudo docker logs realtime-dev.supabase-realtime --tail 20 2>&1 | grep -E "(error|ERROR|warn|WARN|started)" || sudo docker logs realtime-dev.supabase-realtime --tail 10 2>&1
echo ""

echo "--- DATABASE (postgres) ---"
sudo docker logs supabase-db --tail 30 2>&1 | grep -E "(ERROR|FATAL|WARN|ready)" || sudo docker logs supabase-db --tail 15 2>&1
echo ""

# Resource Usage
echo "=== RESOURCE USAGE ==="
echo "Current container resource consumption:"
sudo docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}"
echo ""

echo "System Memory:"
free -h
echo ""

echo "Disk Space:"
df -h | grep -E "Filesystem|/srv|/mnt|/$"
echo ""

# Error Pattern Detection
echo "=== ERROR PATTERN DETECTION ==="
echo "Scanning logs for common issues..."

# Supavisor errors
POOLER_ERRORS=$(sudo docker logs supabase-pooler 2>&1 | grep -i "error\|badarg\|crash" | wc -l)
if [ "$POOLER_ERRORS" -gt 0 ]; then
    echo "⚠ Found $POOLER_ERRORS error(s) in Supavisor logs"
    sudo docker logs supabase-pooler 2>&1 | grep -i "error\|badarg" | tail -5
fi

# Kong errors
KONG_ERRORS=$(sudo docker logs supabase-kong 2>&1 | grep -iE "error|failed|timeout" | wc -l)
if [ "$KONG_ERRORS" -gt 5 ]; then
    echo "⚠ Found $KONG_ERRORS error(s) in Kong logs"
fi

# Database errors
DB_ERRORS=$(sudo docker logs supabase-db 2>&1 | grep -iE "error|fatal" | wc -l)
if [ "$DB_ERRORS" -gt 0 ]; then
    echo "⚠ Found $DB_ERRORS error(s) in Database logs"
fi

if [ "$POOLER_ERRORS" -eq 0 ] && [ "$KONG_ERRORS" -lt 5 ] && [ "$DB_ERRORS" -eq 0 ]; then
    echo "✓ No critical errors detected in logs"
fi
echo ""

# Summary
echo "=== DIAGNOSTIC SUMMARY ==="
TOTAL_CONTAINERS=$(sudo docker compose ps -q | wc -l)
HEALTHY_CONTAINERS=$(sudo docker compose ps | grep healthy | wc -l)
RUNNING_CONTAINERS=$(sudo docker compose ps | grep "Up" | wc -l)

echo "Containers: $RUNNING_CONTAINERS running, $HEALTHY_CONTAINERS healthy, $TOTAL_CONTAINERS total"
echo ""

# Unhealthy containers
UNHEALTHY=$(sudo docker compose ps --format "{{.Name}} {{.Status}}" | grep -v "healthy" | grep -v "NAME" | grep -v "^$")
if [ -n "$UNHEALTHY" ]; then
    echo "⚠ Containers needing attention:"
    echo "$UNHEALTHY"
else
    echo "✓ All containers appear healthy"
fi
echo ""

# Recommendations
echo "=== RECOMMENDATIONS ==="
if [ "$POOLER_ERRORS" -gt 0 ]; then
    echo "• Supavisor has errors - check encryption key formats in .env"
fi
if [ "$DB_ERRORS" -gt 5 ]; then
    echo "• Database has errors - check logs: docker compose logs db"
fi
FREE_SPACE=$(df -h / | tail -1 | awk '{print $4}' | sed 's/G//')
if [ "${FREE_SPACE%%.*}" -lt 10 ]; then
    echo "• Low disk space - consider cleaning up: docker system prune"
fi
AVAILABLE_MEM=$(free -g | grep Mem | awk '{print $7}')
if [ "$AVAILABLE_MEM" -lt 2 ]; then
    echo "• Low available memory - may impact performance"
fi
echo ""

echo "════════════════════════════════════════════════════════════════════════════"
echo "END OF DIAGNOSTIC REPORT"
echo "Save this output for troubleshooting: ./diagnostic.sh > diagnostic-report.txt"
echo "════════════════════════════════════════════════════════════════════════════"
DIAGNOSTIC_EOF

chmod +x "${HELPER_DIR}/diagnostic.sh"
log "Created diagnostic script at ${HELPER_DIR}/diagnostic.sh"
print_success "Diagnostic script created"

print_info "Creating update script..."
cat > "${HELPER_DIR}/update.sh" << 'UPDATE_EOF'
#!/usr/bin/env bash
# Non-destructive update script for Supabase
set -euo pipefail

LOGFILE="/srv/supabase/scripts/update-$(date +%Y%m%d-%H%M%S).log"

# Color definitions
C_CYAN="\033[1;36m"
C_GREEN="\033[1;32m"
C_YELLOW="\033[1;33m"
C_RED="\033[1;31m"
C_WHITE="\033[1;37m"
C_RESET="\033[0m"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE" >/dev/null; }
print_info() { printf "${C_CYAN}◉${C_RESET} %s\n" "$1"; }
print_success() { printf "${C_GREEN}✓${C_RESET} %s\n" "$1"; }
print_warning() { printf "${C_YELLOW}⚠${C_RESET} %s\n" "$1"; }
print_error() { printf "${C_RED}✗${C_RESET} %s\n" "$1" >&2; }

ask_yn() {
  local p="$1" d="${2:-y}" a
  while true; do
        printf "${C_WHITE}%s${C_RESET} [" "$p" >&2
        [[ "$d" = "y" ]] && printf "Y/n" >&2 || printf "y/N" >&2
        printf "]: " >&2
        read -r a </dev/tty || true
        a="${a:-$d}"
        case "$a" in
            y|Y) echo y; return;;
            n|N) echo n; return;;
            *) print_warning "Please enter y or n";;
        esac
  done
}

[[ ${EUID:-$(id -u)} -eq 0 ]] || { print_error "Run as root: sudo bash $0"; exit 1; }

cd /srv/supabase || exit 1

printf "${C_CYAN}Supabase Update Script${C_RESET}\n\n"
log "=== Update started ==="

# Create backup
BACKUP_DIR="/srv/supabase/backups"
mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

print_info "Creating backups..."
cp .env "${BACKUP_DIR}/.env.${TIMESTAMP}" 2>/dev/null || true
cp docker-compose.override.yml "${BACKUP_DIR}/docker-compose.override.yml.${TIMESTAMP}" 2>/dev/null || true

if [[ $(ask_yn "Create database backup?" "y") = "y" ]]; then
    if docker compose ps db | grep -q "healthy"; then
        print_info "Backing up database..."
        docker compose exec -T db pg_dump -U postgres -Fc -d postgres > "${BACKUP_DIR}/db-${TIMESTAMP}.dump" 2>>"$LOGFILE" && \
            print_success "Database backed up" || print_warning "Backup failed"
    fi
fi

# Check for updates
print_info "Checking for Supabase updates..."
docker compose pull 2>&1 | tee -a "$LOGFILE"

# Apply updates
if [[ $(ask_yn "Apply updates?" "y") = "y" ]]; then
    print_info "Applying updates..."
    docker compose up -d >> "$LOGFILE" 2>&1 && print_success "Updated" || { print_error "Update failed"; exit 1; }
    
    print_info "Waiting for services..."
    sleep 15
    
    print_info "Health check..."
    docker compose ps
    
    # Cleanup old images
    if [[ $(ask_yn "Remove old images?" "y") = "y" ]]; then
        print_info "Cleaning up..."
        docker image prune -f >> "$LOGFILE" 2>&1
    fi
    
    # Keep only last 5 backups
    cd "$BACKUP_DIR" && ls -t db-*.dump 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null || true
    
    printf "\n${C_GREEN}✓ Update complete!${C_RESET}\n"
    printf "Backups: ${C_CYAN}%s${C_RESET}\n" "$BACKUP_DIR"
    printf "Log: ${C_CYAN}%s${C_RESET}\n\n" "$LOGFILE"
else
    print_warning "Update cancelled"
fi

log "=== Update completed ==="
UPDATE_EOF

chmod +x "${HELPER_DIR}/update.sh"
log "Created update script at ${HELPER_DIR}/update.sh"
print_success "Update script created"

print_info "Downloading backup and restore utilities..."

# Download backup-from-cloud.sh
if curl -fsSL "https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/backup-from-cloud.sh" \
    -o "${HELPER_DIR}/backup-from-cloud.sh" 2>>"$LOGFILE"; then
    chmod +x "${HELPER_DIR}/backup-from-cloud.sh"
    log "Downloaded backup-from-cloud.sh"
    print_success "Cloud backup utility installed"
else
    print_warning "Failed to download backup-from-cloud.sh"
    log "Failed to download backup-from-cloud.sh"
fi

# Download restore-database.sh
if curl -fsSL "https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/restore-database.sh" \
    -o "${HELPER_DIR}/restore-database.sh" 2>>"$LOGFILE"; then
    chmod +x "${HELPER_DIR}/restore-database.sh"
    log "Downloaded restore-database.sh"
    print_success "Database restore utility installed"
else
    print_warning "Failed to download restore-database.sh"
    log "Failed to download restore-database.sh"
fi

echo
print_success "Helper scripts installed:"
printf "  ${C_CYAN}%s${C_RESET}\n" "${HELPER_DIR}/diagnostic.sh"
printf "  ${C_CYAN}%s${C_RESET}\n" "${HELPER_DIR}/update.sh"
printf "  ${C_CYAN}%s${C_RESET}\n" "${HELPER_DIR}/backup-from-cloud.sh"
printf "  ${C_CYAN}%s${C_RESET}\n" "${HELPER_DIR}/restore-database.sh"

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
printf "${C_WHITE}⚠️  IMPORTANT SECURITY NOTES:${C_RESET}\n"
printf "   • ${C_YELLOW}Never commit .env file to version control${C_RESET}\n"
printf "   • ${C_YELLOW}JWT_SECRET cannot be changed without invalidating all existing API keys${C_RESET}\n"
printf "   • ${C_YELLOW}Clients using ANON_KEY or SERVICE_ROLE_KEY must be updated if JWT_SECRET rotates${C_RESET}\n"
printf "   • ${C_YELLOW}All credentials are securely stored at: /srv/supabase/.env (chmod 600)${C_RESET}\n"
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
print_config_line "API Endpoint (Public)" "$API_URL"
print_config_line "Frontend URL (Your App)" "$SITE_URL"
print_config_line "Studio Dashboard (Admin, Internal)" "http://${LOCAL_IP}:3000"
print_config_line "VM IP Address" "$LOCAL_IP"
echo

printf "${C_WHITE}Helper Scripts (auto-installed):${C_RESET}\n"
echo "  Diagnostic Report:   sudo bash /srv/supabase/scripts/diagnostic.sh"
echo "  Update Supabase:     sudo bash /srv/supabase/scripts/update.sh"
echo "  Backup from Cloud:   sudo bash /srv/supabase/scripts/backup-from-cloud.sh"
echo "  Restore Database:    sudo bash /srv/supabase/scripts/restore-database.sh"
echo

printf "${C_WHITE}Next Steps:${C_RESET}\n"
echo "  ⚠️  IMPORTANT: Studio Dashboard (port 3000) is for ADMIN ACCESS only"
echo "  It should NOT be exposed to the public internet."
echo ""
echo "  Your frontend app ($SITE_URL) should point to your actual application,"
echo "  NOT to Supabase Studio. Studio is only accessible via http://${LOCAL_IP}:3000"
echo ""
echo "  1) Configure reverse proxy for SSL termination:"
echo "     • $API_URL → http://${LOCAL_IP}:${KONG_HTTP_PORT} (Supabase API, enable WebSockets)"
echo "     • $SITE_URL → your JW Writer frontend (NOT port 3000)"
echo "     • (Optional) Create admin.${APEX_FQDN} → http://${LOCAL_IP}:3000 for Studio access"
echo ""
echo "  2) Direct access (for testing on LAN only):"
echo "     • Studio Dashboard: http://${LOCAL_IP}:3000"
echo "     • API Gateway: http://${LOCAL_IP}:${KONG_HTTP_PORT}"
echo "     • Database Pooler: postgresql://postgres.${POOLER_TENANT_ID}:${POSTGRES_PASSWORD}@${LOCAL_IP}:6543/postgres"
echo ""
echo "  3) Run diagnostics: sudo bash /srv/supabase/scripts/diagnostic.sh"
echo "  4) Test your API: curl http://${LOCAL_IP}:${KONG_HTTP_PORT}/health"
echo

printf "${C_CYAN}Installation log: ${C_WHITE}$LOGFILE${C_RESET}\n"
printf "${C_GREEN}✓ Supabase API is up. Access via: $API_URL${C_RESET}\n\n"
