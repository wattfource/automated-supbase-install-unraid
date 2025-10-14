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

animate_light_cycle_intro() {
    clear
    local width=88
    local height=24
    
    # Build empty frame
    local empty_frame="╔"
    for ((i=0; i<width; i++)); do empty_frame+="═"; done
    empty_frame+="╗\n"
    for ((i=0; i<height; i++)); do
        empty_frame+="║"
        for ((j=0; j<width; j++)); do empty_frame+=" "; done
        empty_frame+="║\n"
    done
    empty_frame+="╚"
    for ((i=0; i<width; i++)); do empty_frame+="═"; done
    empty_frame+="╝"
    
    # Animate light cycle racing around the border
    printf "${C_CYAN}"
    
    # Top edge - left to right (sample every 4th position for speed)
    for ((i=0; i<=width; i+=4)); do
        clear
        printf "╔"
        for ((j=0; j<i; j++)); do printf "═"; done
        printf "${C_GREEN}▶${C_CYAN}"
        for ((j=i; j<width; j++)); do printf "═"; done
        printf "╗\n"
        for ((k=0; k<height; k++)); do
            printf "║"
            for ((j=0; j<width; j++)); do printf " "; done
            printf "║\n"
        done
        printf "╚"
        for ((j=0; j<width; j++)); do printf "═"; done
        printf "╝"
        sleep 0.02
    done
    
    # Right edge - top to bottom (sample a few positions)
    for ((i=0; i<=height; i+=2)); do
        clear
        printf "╔"
        for ((j=0; j<width; j++)); do printf "═"; done
        printf "╗\n"
        for ((k=0; k<height; k++)); do
            printf "║"
            for ((j=0; j<width; j++)); do 
                if [[ $k -eq $i && $j -eq $((width-1)) ]]; then
                    printf "${C_GREEN}▼${C_CYAN}"
                else
                    printf " "
                fi
            done
            printf "║\n"
        done
        printf "╚"
        for ((j=0; j<width; j++)); do printf "═"; done
        printf "╝"
        sleep 0.03
    done
    
    # Bottom edge - right to left (sample every 4th position for speed)
    for ((i=width; i>=0; i-=4)); do
        clear
        printf "╔"
        for ((j=0; j<width; j++)); do printf "═"; done
        printf "╗\n"
        for ((k=0; k<height; k++)); do
            printf "║"
            for ((j=0; j<width; j++)); do printf " "; done
            printf "║\n"
        done
        printf "╚"
        for ((j=0; j<i; j++)); do printf "═"; done
        printf "${C_GREEN}◀${C_CYAN}"
        for ((j=i; j<width; j++)); do printf "═"; done
        printf "╝"
        sleep 0.02
    done
    
    printf "${C_RESET}\n"
    
    # Reset terminal state to ensure prompts work properly
    stty sane 2>/dev/null || true
    sleep 0.2
}

print_header() {
    clear
    printf "${C_CYAN}"
    
    # Animated light cycle effect (faster)
    local width=88
    for i in {1..88}; do
        printf "\r╔"
        printf '═%.0s' $(seq 1 $i)
        sleep 0.003
    done
    printf "╗\n"
    
    cat << 'EOF'
║                                                                                      ║
║                                                                                      ║
║        ███████╗██╗   ██╗██████╗  █████╗ ██████╗  █████╗ ███████╗███████╗            ║
║        ██╔════╝██║   ██║██╔══██╗██╔══██╗██╔══██╗██╔══██╗██╔════╝██╔════╝            ║
║        ███████╗██║   ██║██████╔╝███████║██████╔╝███████║███████╗█████╗              ║
║        ╚════██║██║   ██║██╔═══╝ ██╔══██║██╔══██╗██╔══██║╚════██║██╔══╝              ║
║        ███████║╚██████╔╝██║     ██║  ██║██████╔╝██║  ██║███████║███████╗            ║
║        ╚══════╝ ╚═════╝ ╚═╝     ╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝╚══════╝╚══════╝            ║
║                                                                                      ║
║              ██╗   ██╗███╗   ██╗██████╗  █████╗ ██╗██████╗                          ║
║              ██║   ██║████╗  ██║██╔══██╗██╔══██╗██║██╔══██╗                         ║
║              ██║   ██║██╔██╗ ██║██████╔╝███████║██║██║  ██║                         ║
║              ██║   ██║██║╚██╗██║██╔══██╗██╔══██║██║██║  ██║                         ║
║              ╚██████╔╝██║ ╚████║██║  ██║██║  ██║██║██████╔╝                         ║
║               ╚═════╝ ╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚═════╝                          ║
║                                                                                      ║
║        ██╗    ██╗ █████╗ ████████╗████████╗███████╗ ██████╗ ██╗   ██╗██████╗  ██████╗███████╗ ║
║        ██║    ██║██╔══██╗╚══██╔══╝╚══██╔══╝██╔════╝██╔═══██╗██║   ██║██╔══██╗██╔════╝██╔════╝ ║
║        ██║ █╗ ██║███████║   ██║      ██║   █████╗  ██║   ██║██║   ██║██████╔╝██║     █████╗   ║
║        ██║███╗██║██╔══██║   ██║      ██║   ██╔══╝  ██║   ██║██║   ██║██╔══██╗██║     ██╔══╝   ║
║        ╚███╔███╔╝██║  ██║   ██║      ██║   ██║     ╚██████╔╝╚██████╔╝██║  ██║╚██████╗███████╗ ║
║         ╚══╝╚══╝ ╚═╝  ╚═╝   ╚═╝      ╚═╝   ╚═╝      ╚═════╝  ╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚══════╝ ║
║                                                                                      ║
║                    [ LOCAL SUPABASE DEPLOYMENT CONFIGURATION WIZARD ]               ║
║                                                                                      ║
EOF
    
    # Animated bottom border (faster)
    printf "╚"
    for i in {1..88}; do
        printf "═"
        sleep 0.003
    done
    printf "╝\n"
    
    printf "${C_RESET}\n"
    
    # Reset terminal state to ensure prompts work properly
    stty sane 2>/dev/null || true
    sleep 0.2
}

print_step_header() {
    local step="$1"
    local title="$2"
    printf "\n${C_BLUE}"
    printf "╔══════════════════════════════════════════════════════════════════════════════════╗\n"
    printf "║  %-82s ║\n" "STEP $step: $title"
    printf "╚══════════════════════════════════════════════════════════════════════════════════╝\n"
    printf "${C_RESET}\n"
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

upsert_env() {
    local k="$1" v="$2" esc
    esc="$(printf '%s' "$v" | sed -e 's/[&/|]/\\&/g')"
    if grep -q "^${k}=" .env 2>/dev/null; then
        sed -i "s|^${k}=.*|${k}=${esc}|" .env
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

ENABLE_ANALYTICS=$(ask_yn "Enable Analytics/Logs? (requires 2GB+ RAM)" "n")
ENABLE_EMAIL=$(ask_yn "Enable Email Authentication?" "y")
ENABLE_PHONE=$(ask_yn "Enable Phone Authentication?" "n")
ENABLE_ANONYMOUS=$(ask_yn "Enable Anonymous Users?" "n")
ENABLE_STORAGE=$(ask_yn "Enable Storage (file uploads)?" "n")
ENABLE_REALTIME=$(ask_yn "Enable Realtime?" "y")
ENABLE_EDGE=$(ask_yn "Enable Edge Functions?" "n")

log "Feature selection: Analytics=$ENABLE_ANALYTICS Email=$ENABLE_EMAIL Phone=$ENABLE_PHONE Anonymous=$ENABLE_ANONYMOUS Storage=$ENABLE_STORAGE Realtime=$ENABLE_REALTIME Edge=$ENABLE_EDGE"

# STEP 2: Generating Secrets
print_step_header "2" "GENERATING SECRETS"
echo
print_info "Generating crypto-secure secrets..."

POSTGRES_PASSWORD="$(gen_b64 32)"
JWT_SECRET="$(gen_b64 48)"
PG_META_CRYPTO_KEY="$(gen_b64 32)"

log "Generated: POSTGRES_PASSWORD, JWT_SECRET, PG_META_CRYPTO_KEY"
print_success "Secrets generated"

# STEP 3: Database Config
print_step_header "3" "DATABASE CONFIG"
echo
POSTGRES_HOST=$(ask "PostgreSQL Host" "db")
POSTGRES_DB=$(ask "PostgreSQL Database" "postgres")
POSTGRES_PORT=$(ask "PostgreSQL Port" "5432")

log "Database: host=$POSTGRES_HOST db=$POSTGRES_DB port=$POSTGRES_PORT"

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
    APEX_FQDN=$(ask "Apex domain (no subdomain), e.g. example.com" "example.com")
    if valid_domain "$APEX_FQDN" && [[ "$APEX_FQDN" != *.*.*.* ]]; then
        break
    else
        print_warning "Enter a valid apex like example.com"
    fi
done

SITE_URL=$(ask "Frontend URL (SITE_URL)" "http://${LOCAL_IP}:3000")
API_URL=$(ask "Supabase API URL (API_EXTERNAL_URL)" "http://${LOCAL_IP}:8000")
ADDITIONAL_REDIRECT=$(ask "Additional redirect URLs (comma-separated, optional)" "")

log "URLs: apex=$APEX_FQDN site=$SITE_URL api=$API_URL"

# STEP 6: Email Auth Config
print_step_header "6" "EMAIL AUTH CONFIG"
echo

if [[ "$ENABLE_EMAIL" = "y" ]]; then
    EMAIL_AUTOCONFIRM=$(ask_yn "Auto-confirm email signups? (dev only)" "y")
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

# Storage configuration
if [[ "$ENABLE_STORAGE" = "y" ]]; then
    print_step_header "7" "STORAGE CONFIG"
    echo
    
    STORAGE_MOUNT=$(ask "Unraid storage mount path" "/mnt/unraid/supabase-storage/${APEX_FQDN}")
    STORAGE_PROTO=$(ask "Storage protocol (nfs|smb)" "nfs")
    
    if [[ "$STORAGE_PROTO" = "nfs" ]]; then
        UNRAID_HOST=$(ask "Unraid server hostname or IP" "unraid.lan")
        UNRAID_EXPORT="/mnt/user/supabase-storage/${APEX_FQDN}"
        exec_with_spinner "Installing NFS client..." apt install -y nfs-common || {
            print_error "Failed to install NFS client"
            exit 1
        }
    else
        UNRAID_HOST=$(ask "Unraid server hostname or IP" "unraid.lan")
        UNRAID_SHARE="supabase-storage"
        SMB_USER=$(ask "SMB username" "")
        SMB_PASS=$(ask "SMB password" "")
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
print_step_header "8" "SECURITY CONFIG"
echo

PIN_HTTPS_LOOPBACK=$(ask_yn "Pin Kong HTTPS 8443 to localhost (recommended)" "y")
PIN_POOLER_LOOPBACK=$(ask_yn "Pin Supavisor 5432/6543 to localhost (recommended)" "y")
USE_UFW=$(ask_yn "Configure UFW firewall rules?" "n")

if [[ "$USE_UFW" = "y" ]]; then
    NPM_HOST_IP=$(ask "Nginx Proxy Manager host IP" "192.168.1.75")
    ADMIN_SSH_SRC=$(ask "Admin IP/subnet for SSH" "192.168.1.0/24")
    log "Firewall: UFW enabled, NPM=$NPM_HOST_IP SSH=$ADMIN_SSH_SRC"
fi

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
print_config_line "Analytics" "$ENABLE_ANALYTICS"
print_config_line "Email Auth" "$ENABLE_EMAIL"
print_config_line "Phone Auth" "$ENABLE_PHONE"
print_config_line "Storage" "$ENABLE_STORAGE"
print_config_line "Realtime" "$ENABLE_REALTIME"
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
[[ "$USE_UFW" = "y" ]] && print_config_line "Firewall" "Enabled (NPM: $NPM_HOST_IP)"
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
        cp /tmp/supabase/docker/.env.example /srv/supabase/.env 2>/dev/null || touch /srv/supabase/.env || exit 1
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
upsert_env JWT_SECRET "$JWT_SECRET"
upsert_env ANON_KEY "$ANON_KEY"
upsert_env SERVICE_ROLE_KEY "$SERVICE_ROLE_KEY"
upsert_env PG_META_CRYPTO_KEY "$PG_META_CRYPTO_KEY"

# Database
upsert_env POSTGRES_HOST "$POSTGRES_HOST"
upsert_env POSTGRES_DB "$POSTGRES_DB"
upsert_env POSTGRES_PORT "$POSTGRES_PORT"

# Email
upsert_env ENABLE_EMAIL_AUTOCONFIRM "$([[ "$EMAIL_AUTOCONFIRM" = "y" ]] && echo true || echo false)"
upsert_env GOTRUE_SMTP_HOST "$RESEND_SMTP_HOST"
upsert_env GOTRUE_SMTP_PORT "587"
upsert_env GOTRUE_SMTP_USER "resend"
upsert_env GOTRUE_SMTP_PASS "$RESEND_API_KEY"
upsert_env GOTRUE_SMTP_ADMIN_EMAIL "no-reply@$APEX_FQDN"

# Ports
upsert_env KONG_HTTP_PORT "0.0.0.0:$KONG_HTTP_PORT"
[[ "$PIN_HTTPS_LOOPBACK" = "y" ]] && upsert_env KONG_HTTPS_PORT "127.0.0.1:$KONG_HTTPS_PORT"
[[ "$PIN_POOLER_LOOPBACK" = "y" ]] && upsert_env POOLER_PROXY_PORT_TRANSACTION "127.0.0.1:6543"

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
    
    exec_with_spinner "Creating mount point..." mkdir -p "$VM_MOUNT" || {
        print_error "Failed to create mount point"
        exit 1
    }
    
    if [[ "$STORAGE_PROTO" = "nfs" ]]; then
        grep -qE "[[:space:]]$VM_MOUNT[[:space:]]" /etc/fstab || \
            echo "${UNRAID_HOST}:${UNRAID_EXPORT}  ${VM_MOUNT}  nfs  defaults  0  0" >> /etc/fstab
        exec_with_spinner "Mounting NFS share..." mount -a || {
            print_error "Failed to mount NFS share. Check that NFS export exists on Unraid."
            exit 1
        }
    else
        CREDF="/root/.smb-${APEX_FQDN}.cred"
        {
            echo "username=${SMB_USER}"
            echo "password=${SMB_PASS}"
        } > "$CREDF"
        chmod 600 "$CREDF"
        grep -qE "[[:space:]]$VM_MOUNT[[:space:]]" /etc/fstab || \
            echo "//${UNRAID_HOST}/${UNRAID_SHARE}  ${VM_MOUNT}  cifs  credentials=${CREDF},iocharset=utf8  0  0" >> /etc/fstab
        exec_with_spinner "Mounting SMB share..." mount -a || {
            print_error "Failed to mount SMB share. Check credentials and share name."
            exit 1
        }
    fi
    log "Storage mounted at $VM_MOUNT"
fi

# Create docker-compose override
print_info "Creating docker-compose override..."

cat > docker-compose.override.yml <<YAML
services:
  kong:
    ports:
      - "0.0.0.0:${KONG_HTTP_PORT}:8000"
  
  studio:
    ports:
      - "0.0.0.0:3000:3000"
  
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
YAML

if [[ "$ENABLE_STORAGE" = "y" ]]; then
    cat >> docker-compose.override.yml <<YAML
  storage:
    ports: []
    volumes:
      - ${VM_MOUNT}:/var/lib/storage
YAML
fi

if [[ "$ENABLE_ANALYTICS" = "n" ]]; then
    cat >> docker-compose.override.yml <<'YAML'
  analytics:
    profiles: ["dev"]
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

exec_with_spinner "Starting Supabase services..." docker compose up -d || {
    print_error "Failed to start Supabase services. Check Docker logs with: docker compose logs"
    exit 1
}

log "Containers deployed"

# Firewall
if [[ "$USE_UFW" = "y" ]]; then
    print_step_header "◉" "CONFIGURING FIREWALL"
    echo
    
    exec_with_spinner "Installing UFW..." apt install -y ufw iptables-persistent || {
        print_error "Failed to install UFW"
        exit 1
    }
    
    print_info "Configuring firewall rules..."
    ufw --force reset >> "$LOGFILE" 2>&1
    ufw default deny incoming >> "$LOGFILE" 2>&1
    ufw default allow outgoing >> "$LOGFILE" 2>&1
    ufw allow from "$ADMIN_SSH_SRC" to any port 22 proto tcp >> "$LOGFILE" 2>&1
    ufw allow from "$NPM_HOST_IP" to any port "$KONG_HTTP_PORT" proto tcp >> "$LOGFILE" 2>&1
    ufw allow from "$NPM_HOST_IP" to any port 3000 proto tcp >> "$LOGFILE" 2>&1
    ufw --force enable >> "$LOGFILE" 2>&1
    
    iptables -I DOCKER-USER -s "$NPM_HOST_IP" -p tcp --dport 8000 -j ACCEPT >> "$LOGFILE" 2>&1
    iptables -I DOCKER-USER -s "$NPM_HOST_IP" -p tcp --dport 3000 -j ACCEPT >> "$LOGFILE" 2>&1
    iptables -I DOCKER-USER -p tcp --dport 8000 -j DROP >> "$LOGFILE" 2>&1
    iptables -I DOCKER-USER -p tcp --dport 3000 -j DROP >> "$LOGFILE" 2>&1
    iptables -I DOCKER-USER -p tcp --dport 8443 -j DROP >> "$LOGFILE" 2>&1
    iptables -I DOCKER-USER -p tcp --dport 6543 -j DROP >> "$LOGFILE" 2>&1
    iptables -I DOCKER-USER -p tcp --dport 4000 -j DROP >> "$LOGFILE" 2>&1
    netfilter-persistent save >> "$LOGFILE" 2>&1
    
    log "Firewall configured"
    print_success "Firewall configured"
fi

# Completion
log "=== Installation completed successfully ==="

clear

# Animated success banner
printf "${C_CYAN}"
printf "╔"
for i in {1..88}; do
    printf "═"
    sleep 0.005
done
printf "╗\n"

cat << 'EOF'
║                                                                                      ║
║                                                                                      ║
║                    ██████╗ ███████╗██████╗ ██╗      ██████╗ ██╗   ██╗               ║
║                    ██╔══██╗██╔════╝██╔══██╗██║     ██╔═══██╗╚██╗ ██╔╝               ║
║                    ██║  ██║█████╗  ██████╔╝██║     ██║   ██║ ╚████╔╝                ║
║                    ██║  ██║██╔══╝  ██╔═══╝ ██║     ██║   ██║  ╚██╔╝                 ║
║                    ██████╔╝███████╗██║     ███████╗╚██████╔╝   ██║                  ║
║                    ╚═════╝ ╚══════╝╚═╝     ╚══════╝ ╚═════╝    ╚═╝                  ║
║                                                                                      ║
EOF

printf "║                            "
printf "${C_GREEN}"
printf "███████╗██╗   ██╗ ██████╗ ██████╗███████╗███████╗███████╗"
printf "${C_CYAN}"
printf "                ║\n"

printf "║                            "
printf "${C_GREEN}"
printf "██╔════╝██║   ██║██╔════╝██╔════╝██╔════╝██╔════╝██╔════╝"
printf "${C_CYAN}"
printf "                ║\n"

printf "║                            "
printf "${C_GREEN}"
printf "███████╗██║   ██║██║     ██║     █████╗  ███████╗███████╗"
printf "${C_CYAN}"
printf "                ║\n"

printf "║                            "
printf "${C_GREEN}"
printf "╚════██║██║   ██║██║     ██║     ██╔══╝  ╚════██║╚════██║"
printf "${C_CYAN}"
printf "                ║\n"

printf "║                            "
printf "${C_GREEN}"
printf "███████║╚██████╔╝╚██████╗╚██████╗███████╗███████║███████║"
printf "${C_CYAN}"
printf "                ║\n"

printf "║                            "
printf "${C_GREEN}"
printf "╚══════╝ ╚═════╝  ╚═════╝ ╚═════╝╚══════╝╚══════╝╚══════╝"
printf "${C_CYAN}"
printf "                ║\n"

cat << 'EOF'
║                                                                                      ║
║                                                                                      ║
╚══════════════════════════════════════════════════════════════════════════════════════╝
EOF
printf "${C_RESET}\n\n"

printf "${C_WHITE}Access Your Supabase Instance:${C_RESET}\n"
print_config_line "Studio Dashboard" "$SITE_URL"
print_config_line "API Endpoint" "$API_URL"
print_config_line "Anon Key" "${ANON_KEY:0:40}..."
echo

printf "${C_WHITE}Next Steps:${C_RESET}\n"
echo "  1) Configure Nginx Proxy Manager to proxy to this VM"
echo "  2) Set up SSL certificates in NPM"
echo "  3) Test your API endpoint"
echo "  4) Visit the Studio dashboard to create your first project"
echo

printf "${C_CYAN}Installation log: ${C_WHITE}$LOGFILE${C_RESET}\n"
printf "${C_CYAN}════════════════════════════════════════════════════════════════════════════════════════${C_RESET}\n"
printf "${C_GREEN}✓ SUPABASE ${C_CYAN}× ${C_BLUE}UNRAID ${C_CYAN}× ${C_MAGENTA}WATTFOURCE ${C_CYAN}Grid deployment complete!${C_RESET}\n"
printf "${C_CYAN}════════════════════════════════════════════════════════════════════════════════════════${C_RESET}\n\n"
