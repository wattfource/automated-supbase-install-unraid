#!/usr/bin/env bash
# ============================================================================
# WATTFOURCE SUPABASE INSTALLER
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
    printf "${C_CYAN}WATTFOURCE${C_RESET} — Supabase Local Setup Configuration Wizard\n"
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

gen_b64() { openssl rand -base64 "$1" 2>>"$LOGFILE"; }
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

# Function to validate and clean .env file
validate_env_file() {
    if [[ ! -f .env ]]; then
        return 0
    fi

    log "Validating .env file format..."
    local temp_file=".env.tmp"

    # Filter out malformed lines and keep only valid KEY=VALUE lines
    # Remove any lines that don't follow proper KEY=VALUE format
    # Remove template entries and empty lines
    grep -E '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=' .env | \
    grep -v "your-super-secret" | \
    grep -v "your-encryption-key" | \
    grep -v "your-tenant-id" | \
    grep -v "GOOGLE_PROJECT_ID" | \
    grep -v "GOOGLE_PROJECT_NUMBER" | \
    grep -v "^[[:space:]]*$" | \
    grep -v '^[^=]*$' > "$temp_file" 2>/dev/null || true

    if [[ -s "$temp_file" ]]; then
        mv "$temp_file" .env
        log "Cleaned malformed and template entries from .env file"
    else
        rm -f "$temp_file"
        log "Warning: .env file appears to be corrupted, recreating..."
        > .env
    fi
}

upsert_env() {
    local k="$1" v="$2"

    # Ensure .env file is clean before writing
    validate_env_file

    # Remove existing line for this key if it exists
    if [[ -f .env ]] && grep -q "^${k}=" .env 2>/dev/null; then
        sed -i "/^${k}=/d" .env 2>/dev/null || true
    fi

    # Escape value for .env file - quote values that could break docker-compose parsing
    # Docker-compose treats unquoted values with / as variable separators
    if [[ "$v" =~ [/\$\`\"\'\\] ]]; then
        # Value contains characters that docker-compose might misinterpret - quote it
        printf '%s="%s"\n' "$k" "$v" >> .env
    else
        # Value is safe to leave unquoted
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

# Clean up broken configurations from previous failed installations
cleanup_previous_attempts() {
    local cleaned=0
    
    # Check for broken Docker repository (repository exists but GPG key doesn't)
    if [[ -f /etc/apt/sources.list.d/docker.list ]] && [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
        log "Detected broken Docker repository configuration from previous attempt"
        print_warning "Cleaning up broken Docker repository configuration..."
        rm -f /etc/apt/sources.list.d/docker.list 2>/dev/null || true
        cleaned=1
    fi
    
    # Check for orphaned Docker keyring directory
    if [[ -d /etc/apt/keyrings ]] && [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
        # Remove only if it's empty or contains broken Docker keys
        if [[ -z "$(ls -A /etc/apt/keyrings 2>/dev/null)" ]]; then
            rmdir /etc/apt/keyrings 2>/dev/null || true
        fi
    fi
    
    # Clean up any partial Supabase installations
    if [[ -d "/srv/supabase" ]] && [[ ! -f "/srv/supabase/docker-compose.yml" ]]; then
        log "Detected incomplete Supabase installation directory"
        print_warning "Cleaning up incomplete Supabase installation..."
        rm -rf /srv/supabase 2>/dev/null || true
        cleaned=1
    fi
    
    # Clean up any orphaned Docker containers from previous attempts
    if command -v docker >/dev/null 2>&1; then
        local orphaned_containers=$(docker ps -a --filter "name=supabase" --format "{{.Names}}" 2>/dev/null || true)
        if [[ -n "$orphaned_containers" ]]; then
            log "Found orphaned Supabase containers from previous attempts"
            print_warning "Cleaning up orphaned Docker containers..."
            docker stop $(echo "$orphaned_containers") 2>/dev/null || true
            docker rm $(echo "$orphaned_containers") 2>/dev/null || true
            cleaned=1
        fi
    fi
    
    # If we cleaned anything, update apt cache
    if [[ $cleaned -eq 1 ]]; then
        log "Running apt update to refresh package lists..."
        apt update >> "$LOGFILE" 2>&1 || {
            log "Warning: apt update failed, but continuing anyway"
        }
        print_success "Cleanup complete"
    fi
}

# Clean up any broken configurations from previous failed installations
cleanup_previous_attempts

# Show epic light cycle animation intro (set SKIP_ANIMATION=1 to disable)
if [[ "${SKIP_ANIMATION:-0}" != "1" ]]; then
    animate_light_cycle_intro
fi

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
PG_META_CRYPTO_KEY="$(gen_b64 32)"
SECRET_KEY_BASE="$(gen_b64 64)"
VAULT_ENC_KEY="$(gen_b64 32)"
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

# Firewall config
print_step_header "9" "SECURITY CONFIG"
echo

PIN_HTTPS_LOOPBACK=$(ask_yn "Pin Kong HTTPS 8443 to localhost (recommended)" "y")
PIN_POOLER_LOOPBACK=$(ask_yn "Pin Supavisor 5432/6543 to localhost (recommended)" "y")

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

printf "${C_WHITE}Security:${C_RESET}\n"
print_config_line "HTTPS Pinned" "$([[ "$PIN_HTTPS_LOOPBACK" = "y" ]] && echo "127.0.0.1:8443" || echo "0.0.0.0:8443")"
print_config_line "Pooler Pinned" "$([[ "$PIN_POOLER_LOOPBACK" = "y" ]] && echo "127.0.0.1:5432/6543" || echo "Network accessible")"
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

# Install dependencies
print_step_header "◉" "INSTALLING DEPENDENCIES"
echo

# Install basic tools first (needed for Docker installation)
print_info "Installing prerequisite packages..."
for cmd in curl gpg jq openssl git; do
    if ! command -v $cmd >/dev/null; then
        exec_with_spinner "Installing $cmd..." apt install -y $cmd || {
            print_error "Failed to install $cmd"
            exit 1
        }
    else
        print_success "$cmd already installed"
    fi
done

# Now install Docker (which requires curl and gpg)
if ! command -v docker >/dev/null; then
    print_info "Installing Docker Engine..."
    exec_with_spinner "Adding Docker repository..." bash -c '
        set -euo pipefail
        install -m 0755 -d /etc/apt/keyrings || exit 1
        curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg || exit 1
        chmod a+r /etc/apt/keyrings/docker.gpg || exit 1
        . /etc/os-release || exit 1
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $VERSION_CODENAME stable" > /etc/apt/sources.list.d/docker.list || exit 1
        apt update || exit 1
    ' || {
        print_error "Failed to add Docker repository. Please check your internet connection."
        exit 1
    }
    
    exec_with_spinner "Installing Docker packages..." bash -c '
        set -euo pipefail
        apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || exit 1
    ' || {
        print_error "Docker installation failed."
        print_error "You may need to install Docker manually: https://docs.docker.com/engine/install/debian/"
        exit 1
    }
    
    exec_with_spinner "Enabling Docker service..." systemctl enable --now docker || {
        print_error "Failed to start Docker service"
        exit 1
    }
    
    print_success "Docker Engine installed successfully"
else
    print_success "Docker already installed"
fi

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
if [[ ! -f docker-compose.yml ]]; then
    exec_with_spinner "Fetching Supabase docker bundle..." bash -c "
        set -euo pipefail
        rm -rf /tmp/supabase || exit 1
        git clone --depth 1 https://github.com/supabase/supabase /tmp/supabase || exit 1
        cp -rf /tmp/supabase/docker/* /srv/supabase/ || exit 1
        # Create a clean .env file instead of copying .env.example (which contains template entries)
        touch /srv/supabase/.env || exit 1
        rm -rf /tmp/supabase || exit 1
    " || {
        print_error "Failed to download Supabase bundle. Please check your internet connection."
        exit 1
    }
else
    print_success "Supabase bundle already exists"
fi

# Backup existing env
if [[ -f .env ]]; then
cp -a .env ".env.bak.$(date +%F-%H%M%S)"
    log "Backed up existing .env file"
fi

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

print_info "Validating and cleaning .env file..."
validate_env_file

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

# Determine port bindings based on pinning preferences


# Create docker-compose override for security and feature configuration
cat > docker-compose.override.yml <<YAML
services:
YAML

# Only add port overrides when we need to change from defaults
# Default ports: Kong HTTP=8000, Kong HTTPS=8443, Pooler=6543
if [[ "$PIN_HTTPS_LOOPBACK" = "y" ]] || [[ "$PIN_POOLER_LOOPBACK" = "y" ]] || [[ "$KONG_HTTP_PORT" != "8000" ]]; then

    # Kong HTTP port override (only if different from default 8000)
    if [[ "$KONG_HTTP_PORT" != "8000" ]]; then
        cat >> docker-compose.override.yml <<YAML
  kong:
    ports:
      - "${KONG_HTTP_PORT}:8000"
YAML
    fi

    # Kong HTTPS port override (only if pinning to localhost)
    if [[ "$PIN_HTTPS_LOOPBACK" = "y" ]]; then
        cat >> docker-compose.override.yml <<YAML
  kong:
    ports:
      - "127.0.0.1:${KONG_HTTPS_PORT}:8443"
YAML
    fi

    # Supavisor port override (only if pinning to localhost)
    if [[ "$PIN_POOLER_LOOPBACK" = "y" ]]; then
        cat >> docker-compose.override.yml <<YAML
  supavisor:
    ports:
      - "127.0.0.1:6543:6543"
YAML
    fi
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

# Deploy containers
print_step_header "◉" "DEPLOYING CONTAINERS"
echo

exec_with_spinner "Pulling container images (this may take a while)..." docker compose pull || {
    print_error "Failed to pull Docker images. Please check your internet connection and Docker installation."
    exit 1
}

# Clean up any existing containers to avoid conflicts
print_info "Cleaning up any existing Supabase containers..."
docker compose down 2>/dev/null || true

# Start services in correct order - database first, then others
print_info "Starting database service..."
docker compose up -d db || {
    print_error "Failed to start database service"
    exit 1
}

# Wait for database to be ready
print_info "Waiting for database to be healthy..."
for i in {1..30}; do
    if docker compose ps db | grep -q "healthy"; then
        break
    fi
    sleep 2
done

if ! docker compose ps db | grep -q "healthy"; then
    print_warning "Database may not be fully ready, but continuing..."
fi

# Start remaining services
exec_with_spinner "Starting remaining Supabase services..." docker compose up -d || {
    print_error "Failed to start Supabase services. Check Docker logs with: docker compose logs"
    exit 1
}

log "Containers deployed"


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
echo "  2) Or access directly: http://${LOCAL_IP}:${KONG_HTTP_PORT} (API) / http://${LOCAL_IP}:3000 (Studio)"
echo "  3) Test your API endpoint and visit Studio dashboard"
echo

printf "${C_CYAN}Installation log: ${C_WHITE}$LOGFILE${C_RESET}\n"
printf "${C_GREEN}✓ Supabase stack is up. Studio: $SITE_URL  API: $API_URL${C_RESET}\n\n"
