#!/bin/bash
# ============================================================================
# SUPABASE CONFIGURATION UPDATE UTILITY
#
# Interactively view and update all Supabase configuration values
# Shows current values and allows editing individual settings
# Automatically restarts services to apply changes
#
# Usage:
#   sudo bash update-supabase.sh
# ============================================================================
set -euo pipefail

# Color definitions
C_CYAN="\033[1;36m"
C_BLUE="\033[1;34m"
C_GREEN="\033[1;32m"
C_YELLOW="\033[1;33m"
C_RED="\033[1;31m"
C_WHITE="\033[1;37m"
C_RESET="\033[0m"

print_header() {
    clear
    printf "${C_CYAN}╔════════════════════════════════════════════════════════════════╗${C_RESET}\n"
    printf "${C_CYAN}║         SUPABASE CONFIGURATION UPDATE UTILITY                  ║${C_RESET}\n"
    printf "${C_CYAN}╚════════════════════════════════════════════════════════════════╝${C_RESET}\n\n"
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

print_section() {
    printf "\n${C_BLUE}━━ %s ━━${C_RESET}\n\n" "$1"
}

ask() {
    local p="$1" d="${2-}" v
    printf "${C_WHITE}%s${C_RESET}" "$p"
    [[ -n "$d" ]] && printf " ${C_CYAN}[%s]${C_RESET}" "$d"
    printf ": " >&2
    read -r v </dev/tty
    echo "${v:-$d}"
}

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

require_root() {
    [[ ${EUID:-$(id -u)} -eq 0 ]] || {
        print_error "This script must be run as root. Use: sudo bash $0"
        exit 1
    }
}

# Secret Generation Functions
gen_b64_url() { openssl rand "$1" 2>/dev/null | base64 | tr '+/' '-_' | tr -d '=' | tr -d '\n'; }

b64url() { openssl enc -base64 -A | tr '+/' '-_' | tr -d '='; }

gen_jwt_for_role() {
  local role="$1" header payload hb pb sig iat exp JWT_SECRET="$2"
  iat=$(date +%s); exp=$((iat + 3600*24*365*5))
  header='{"typ":"JWT","alg":"HS256"}'
  payload="$(jq -nc --arg r "$role" --argjson i "$iat" --argjson e "$exp" \
        '{"role":$r,"iss":"supabase","iat":$i,"exp":$e}' 2>/dev/null)"
  hb="$(printf '%s' "$header" | b64url)"
  pb="$(printf '%s' "$payload" | b64url)"
  sig="$(printf '%s.%s' "$hb" "$pb" | openssl dgst -binary -sha256 -hmac "$JWT_SECRET" | b64url 2>/dev/null)"
  printf '%s.%s.%s\n' "$hb" "$pb" "$sig"
}

ask_secret_action() {
    local prompt="$1" current_val="$2" action
    echo
    printf "${C_CYAN}Current value:${C_RESET} %s\n" "${current_val:-(not set)}"
    printf "${C_WHITE}Choose action:${C_RESET}\n"
    echo "  [K] Keep current value"
    echo "  [G] Generate new value"
    echo "  [E] Enter custom value"
    echo
    while true; do
        read -p "Action [K/G/E]: " -r action </dev/tty || true
        action="${action:-K}"
        case "$action" in
            K|k) echo "keep"; return;;
            G|g) echo "generate"; return;;
            E|e) echo "enter"; return;;
            *) print_warning "Please enter K, G, or E";;
        esac
    done
}

check_supabase_directory() {
    if [ ! -d "/srv/supabase" ]; then
        print_error "Supabase installation not found at /srv/supabase"
        exit 1
    fi
    
    if [ ! -f "/srv/supabase/.env" ]; then
        print_error ".env file not found in /srv/supabase"
        exit 1
    fi
}

# Get value from .env file
get_env_value() {
    local key="$1"
    local file="/srv/supabase/.env"
    
    if [ -f "$file" ]; then
        grep "^${key}=" "$file" 2>/dev/null | cut -d'=' -f2- || echo ""
    else
        echo ""
    fi
}

# Update value in .env file
update_env_value() {
    local key="$1"
    local value="$2"
    local file="/srv/supabase/.env"
    
    if grep -q "^${key}=" "$file"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$file"
    else
        echo "${key}=${value}" >> "$file"
    fi
}

# ============================================================================
# MAIN
# ============================================================================

require_root
print_header

check_supabase_directory

# Read all current values
print_info "Loading current configuration..."

# Auth & Security
SITE_URL=$(get_env_value "SITE_URL")
API_EXTERNAL_URL=$(get_env_value "API_EXTERNAL_URL")
ADDITIONAL_REDIRECT_URLS=$(get_env_value "ADDITIONAL_REDIRECT_URLS")
JWT_SECRET=$(get_env_value "JWT_SECRET")
JWT_EXPIRY=$(get_env_value "JWT_EXPIRY")
ANON_KEY=$(get_env_value "ANON_KEY")
SERVICE_ROLE_KEY=$(get_env_value "SERVICE_ROLE_KEY")
SUPABASE_PUBLIC_URL=$(get_env_value "SUPABASE_PUBLIC_URL")

# Database
POSTGRES_HOST=$(get_env_value "POSTGRES_HOST")
POSTGRES_DB=$(get_env_value "POSTGRES_DB")
POSTGRES_PORT=$(get_env_value "POSTGRES_PORT")

# Email/SMTP
SMTP_HOST=$(get_env_value "SMTP_HOST")
SMTP_PORT=$(get_env_value "SMTP_PORT")
SMTP_USER=$(get_env_value "SMTP_USER")
SMTP_ADMIN_EMAIL=$(get_env_value "SMTP_ADMIN_EMAIL")
SMTP_SENDER_NAME=$(get_env_value "SMTP_SENDER_NAME")
ENABLE_EMAIL_SIGNUP=$(get_env_value "ENABLE_EMAIL_SIGNUP")
ENABLE_EMAIL_AUTOCONFIRM=$(get_env_value "ENABLE_EMAIL_AUTOCONFIRM")

# Auth Features
ENABLE_PHONE_SIGNUP=$(get_env_value "ENABLE_PHONE_SIGNUP")
ENABLE_PHONE_AUTOCONFIRM=$(get_env_value "ENABLE_PHONE_AUTOCONFIRM")
ENABLE_ANONYMOUS_USERS=$(get_env_value "ENABLE_ANONYMOUS_USERS")
DISABLE_SIGNUP=$(get_env_value "DISABLE_SIGNUP")

# Twilio SMS Provider
TWILIO_ACCOUNT_SID=$(get_env_value "TWILIO_ACCOUNT_SID")
TWILIO_AUTH_TOKEN=$(get_env_value "TWILIO_AUTH_TOKEN")
TWILIO_PHONE_NUMBER=$(get_env_value "TWILIO_PHONE_NUMBER")

# Studio
DASHBOARD_USERNAME=$(get_env_value "DASHBOARD_USERNAME")
STUDIO_DEFAULT_ORGANIZATION=$(get_env_value "STUDIO_DEFAULT_ORGANIZATION")
STUDIO_DEFAULT_PROJECT=$(get_env_value "STUDIO_DEFAULT_PROJECT")

# API
PGRST_DB_SCHEMAS=$(get_env_value "PGRST_DB_SCHEMAS")

# Other
POOLER_TENANT_ID=$(get_env_value "POOLER_TENANT_ID")

echo

print_section "AUTHENTICATION & SECURITY"

print_info "Current Settings:"
printf "  ${C_CYAN}SITE_URL${C_RESET}: %s\n" "${SITE_URL:-(not set)}"
printf "  ${C_CYAN}API_EXTERNAL_URL${C_RESET}: %s\n" "${API_EXTERNAL_URL:-(not set)}"
printf "  ${C_CYAN}ADDITIONAL_REDIRECT_URLS${C_RESET}: %s\n" "${ADDITIONAL_REDIRECT_URLS:-(not set)}"
printf "  ${C_CYAN}JWT_EXPIRY${C_RESET}: %s seconds\n" "${JWT_EXPIRY:-3600}"

echo
print_warning "⚠️  JWT Secret Rotation Notice:"
echo "  If you change the JWT_SECRET below, it will invalidate all existing API keys."
echo "  Any clients using ANON_KEY or SERVICE_ROLE_KEY will need to be updated."
echo

# Optional JWT secret rotation
if [[ $(ask_yn "Manage JWT secrets?" "n") = "y" ]]; then
    JWT_ACTION=$(ask_secret_action "JWT_SECRET" "${JWT_SECRET:0:20}...")
    case "$JWT_ACTION" in
        generate)
            JWT_SECRET=$(gen_b64_url 48)
            export JWT_SECRET
            ANON_KEY=$(gen_jwt_for_role "anon" "$JWT_SECRET")
            SERVICE_ROLE_KEY=$(gen_jwt_for_role "service_role" "$JWT_SECRET")
            print_success "✓ JWT_SECRET rotated and API keys regenerated"
            print_warning "⚠️  Update all client applications with new ANON_KEY:"
            printf "     ${C_YELLOW}%s${C_RESET}\n" "${ANON_KEY:0:30}..."
            ;;
        enter)
            JWT_SECRET=$(ask "Enter new JWT_SECRET" "$JWT_SECRET")
            export JWT_SECRET
            ANON_KEY=$(gen_jwt_for_role "anon" "$JWT_SECRET")
            SERVICE_ROLE_KEY=$(gen_jwt_for_role "service_role" "$JWT_SECRET")
            print_success "✓ JWT_SECRET updated and API keys regenerated"
            ;;
        keep)
            print_info "Keeping current JWT_SECRET"
            ;;
    esac
fi

echo

if [[ $(ask_yn "Update other authentication settings?" "n") = "y" ]]; then
    SITE_URL=$(ask "SITE_URL (primary app URL for auth redirects)" "$SITE_URL")
    API_EXTERNAL_URL=$(ask "API_EXTERNAL_URL (Supabase API endpoint)" "$API_EXTERNAL_URL")
    ADDITIONAL_REDIRECT_URLS=$(ask "ADDITIONAL_REDIRECT_URLS (comma-separated)" "${ADDITIONAL_REDIRECT_URLS}")
    JWT_EXPIRY=$(ask "JWT_EXPIRY (seconds)" "${JWT_EXPIRY:-3600}")
fi

print_section "EMAIL / SMTP CONFIGURATION"

print_info "Current Settings:"
printf "  ${C_CYAN}SMTP_HOST${C_RESET}: %s\n" "${SMTP_HOST:-(not set)}"
printf "  ${C_CYAN}SMTP_PORT${C_RESET}: %s\n" "${SMTP_PORT:-(not set)}"
printf "  ${C_CYAN}SMTP_USER${C_RESET}: %s\n" "${SMTP_USER:-(not set)}"
printf "  ${C_CYAN}SMTP_ADMIN_EMAIL${C_RESET}: %s\n" "${SMTP_ADMIN_EMAIL:-(not set)}"
printf "  ${C_CYAN}SMTP_SENDER_NAME${C_RESET}: %s\n" "${SMTP_SENDER_NAME:-(not set)}"
printf "  ${C_CYAN}ENABLE_EMAIL_SIGNUP${C_RESET}: %s\n" "${ENABLE_EMAIL_SIGNUP:-true}"
printf "  ${C_CYAN}ENABLE_EMAIL_AUTOCONFIRM${C_RESET}: %s\n" "${ENABLE_EMAIL_AUTOCONFIRM:-false}"

echo

if [[ $(ask_yn "Update email/SMTP settings?" "n") = "y" ]]; then
    SMTP_HOST=$(ask "SMTP_HOST" "$SMTP_HOST")
    SMTP_PORT=$(ask "SMTP_PORT" "$SMTP_PORT")
    SMTP_USER=$(ask "SMTP_USER" "$SMTP_USER")
    SMTP_ADMIN_EMAIL=$(ask "SMTP_ADMIN_EMAIL (from email)" "$SMTP_ADMIN_EMAIL")
    SMTP_SENDER_NAME=$(ask "SMTP_SENDER_NAME" "$SMTP_SENDER_NAME")
    ENABLE_EMAIL_SIGNUP=$(ask "ENABLE_EMAIL_SIGNUP (true/false)" "${ENABLE_EMAIL_SIGNUP:-true}")
    ENABLE_EMAIL_AUTOCONFIRM=$(ask "ENABLE_EMAIL_AUTOCONFIRM (true/false, dev only)" "${ENABLE_EMAIL_AUTOCONFIRM:-false}")
fi

print_section "AUTH FEATURES"

print_info "Current Settings:"
printf "  ${C_CYAN}ENABLE_PHONE_SIGNUP${C_RESET}: %s\n" "${ENABLE_PHONE_SIGNUP:-false}"
printf "  ${C_CYAN}ENABLE_PHONE_AUTOCONFIRM${C_RESET}: %s\n" "${ENABLE_PHONE_AUTOCONFIRM:-false}"
printf "  ${C_CYAN}ENABLE_ANONYMOUS_USERS${C_RESET}: %s\n" "${ENABLE_ANONYMOUS_USERS:-false}"
printf "  ${C_CYAN}DISABLE_SIGNUP${C_RESET}: %s\n" "${DISABLE_SIGNUP:-false}"

if [[ -n "$TWILIO_ACCOUNT_SID" ]]; then
    printf "  ${C_CYAN}TWILIO_ACCOUNT_SID${C_RESET}: %s\n" "${TWILIO_ACCOUNT_SID:0:10}..."
    printf "  ${C_CYAN}TWILIO_PHONE_NUMBER${C_RESET}: %s\n" "$TWILIO_PHONE_NUMBER"
fi

echo
print_info "📱 PHONE AUTHENTICATION SETUP GUIDE:"
echo "   Phone authentication uses SMS-based one-time passwords (OTP)"
echo "   ENABLE_PHONE_SIGNUP: true/false - Allow users to sign up with phone numbers"
echo "   ENABLE_PHONE_AUTOCONFIRM: true/false - Auto-confirm phone numbers (dev/testing only!)"
echo ""
echo "   ⚠️  IMPORTANT: To use phone authentication, you must configure an SMS provider:"
echo "   Supported providers:"
echo "     • Twilio (most popular)"
echo "     • Vonage/Nexmo"
echo "     • MessageBird"
echo "     • Textlocal"
echo ""
echo "   SMS provider configuration is done in Supabase auth settings."
echo "   After enabling phone signup, visit your Supabase Studio dashboard"
echo "   and configure your SMS provider credentials under Auth settings."
echo ""

if [[ $(ask_yn "Update auth features?" "n") = "y" ]]; then
    ENABLE_PHONE_SIGNUP=$(ask "ENABLE_PHONE_SIGNUP (true/false)" "${ENABLE_PHONE_SIGNUP:-false}")
    ENABLE_PHONE_AUTOCONFIRM=$(ask "ENABLE_PHONE_AUTOCONFIRM (true/false)" "${ENABLE_PHONE_AUTOCONFIRM:-false}")
    ENABLE_ANONYMOUS_USERS=$(ask "ENABLE_ANONYMOUS_USERS (true/false)" "${ENABLE_ANONYMOUS_USERS:-false}")
    DISABLE_SIGNUP=$(ask "DISABLE_SIGNUP (true/false)" "${DISABLE_SIGNUP:-false}")
    
    if [[ "$ENABLE_PHONE_SIGNUP" = "true" ]]; then
        if [[ $(ask_yn "Configure Twilio credentials?" "n") = "y" ]]; then
            TWILIO_ACCOUNT_SID=$(ask "Twilio Account SID" "${TWILIO_ACCOUNT_SID}")
            TWILIO_AUTH_TOKEN=$(ask "Twilio Auth Token" "${TWILIO_AUTH_TOKEN}")
            TWILIO_PHONE_NUMBER=$(ask "Twilio Phone Number (e.g., +1234567890)" "${TWILIO_PHONE_NUMBER}")
        fi
    fi
fi

print_section "STUDIO DASHBOARD"

print_info "Current Settings:"
printf "  ${C_CYAN}DASHBOARD_USERNAME${C_RESET}: %s\n" "${DASHBOARD_USERNAME:-supabase}"
printf "  ${C_CYAN}STUDIO_DEFAULT_ORGANIZATION${C_RESET}: %s\n" "${STUDIO_DEFAULT_ORGANIZATION:-Default Organization}"
printf "  ${C_CYAN}STUDIO_DEFAULT_PROJECT${C_RESET}: %s\n" "${STUDIO_DEFAULT_PROJECT:-Default Project}"

echo

if [[ $(ask_yn "Update studio settings?" "n") = "y" ]]; then
    DASHBOARD_USERNAME=$(ask "DASHBOARD_USERNAME" "${DASHBOARD_USERNAME:-supabase}")
    STUDIO_DEFAULT_ORGANIZATION=$(ask "STUDIO_DEFAULT_ORGANIZATION" "${STUDIO_DEFAULT_ORGANIZATION:-Default Organization}")
    STUDIO_DEFAULT_PROJECT=$(ask "STUDIO_DEFAULT_PROJECT" "${STUDIO_DEFAULT_PROJECT:-Default Project}")
fi

print_section "DATABASE & API"

print_info "Current Settings:"
printf "  ${C_CYAN}POSTGRES_HOST${C_RESET}: %s\n" "${POSTGRES_HOST:-db}"
printf "  ${C_CYAN}POSTGRES_DB${C_RESET}: %s\n" "${POSTGRES_DB:-postgres}"
printf "  ${C_CYAN}POSTGRES_PORT${C_RESET}: %s\n" "${POSTGRES_PORT:-5432}"
printf "  ${C_CYAN}PGRST_DB_SCHEMAS${C_RESET}: %s\n" "${PGRST_DB_SCHEMAS:-public,storage,graphql_public}"
printf "  ${C_CYAN}POOLER_TENANT_ID${C_RESET}: %s\n" "${POOLER_TENANT_ID:-supabase-local}"

echo

if [[ $(ask_yn "Update database/API settings?" "n") = "y" ]]; then
    POSTGRES_HOST=$(ask "POSTGRES_HOST" "${POSTGRES_HOST:-db}")
    POSTGRES_DB=$(ask "POSTGRES_DB" "${POSTGRES_DB:-postgres}")
    POSTGRES_PORT=$(ask "POSTGRES_PORT" "${POSTGRES_PORT:-5432}")
    PGRST_DB_SCHEMAS=$(ask "PGRST_DB_SCHEMAS (comma-separated)" "${PGRST_DB_SCHEMAS:-public,storage,graphql_public}")
    POOLER_TENANT_ID=$(ask "POOLER_TENANT_ID" "${POOLER_TENANT_ID:-supabase-local}")
fi

print_section "SUMMARY OF CHANGES"

# Compare and show what will change
CHANGES=0

# Check for changes
if [ "$(get_env_value SITE_URL)" != "$SITE_URL" ]; then
    echo "${C_YELLOW}SITE_URL${C_RESET}"
    echo "  Before: $(get_env_value SITE_URL)"
    echo "  After:  $SITE_URL"
    CHANGES=$((CHANGES+1))
fi

if [ "$(get_env_value API_EXTERNAL_URL)" != "$API_EXTERNAL_URL" ]; then
    echo "${C_YELLOW}API_EXTERNAL_URL${C_RESET}"
    echo "  Before: $(get_env_value API_EXTERNAL_URL)"
    echo "  After:  $API_EXTERNAL_URL"
    CHANGES=$((CHANGES+1))
fi

if [ "$(get_env_value ADDITIONAL_REDIRECT_URLS)" != "$ADDITIONAL_REDIRECT_URLS" ]; then
    echo "${C_YELLOW}ADDITIONAL_REDIRECT_URLS${C_RESET}"
    echo "  Before: $(get_env_value ADDITIONAL_REDIRECT_URLS)"
    echo "  After:  $ADDITIONAL_REDIRECT_URLS"
    CHANGES=$((CHANGES+1))
fi

if [ "$(get_env_value SMTP_HOST)" != "$SMTP_HOST" ]; then
    echo "${C_YELLOW}SMTP_HOST${C_RESET}"
    echo "  Before: $(get_env_value SMTP_HOST)"
    echo "  After:  $SMTP_HOST"
    CHANGES=$((CHANGES+1))
fi

if [ "$(get_env_value SMTP_PORT)" != "$SMTP_PORT" ]; then
    echo "${C_YELLOW}SMTP_PORT${C_RESET}"
    echo "  Before: $(get_env_value SMTP_PORT)"
    echo "  After:  $SMTP_PORT"
    CHANGES=$((CHANGES+1))
fi

if [ "$(get_env_value DASHBOARD_USERNAME)" != "$DASHBOARD_USERNAME" ]; then
    echo "${C_YELLOW}DASHBOARD_USERNAME${C_RESET}"
    echo "  Before: $(get_env_value DASHBOARD_USERNAME)"
    echo "  After:  $DASHBOARD_USERNAME"
    CHANGES=$((CHANGES+1))
fi

if [ "$(get_env_value ENABLE_PHONE_SIGNUP)" != "$ENABLE_PHONE_SIGNUP" ]; then
    echo "${C_YELLOW}ENABLE_PHONE_SIGNUP${C_RESET}"
    echo "  Before: $(get_env_value ENABLE_PHONE_SIGNUP)"
    echo "  After:  $ENABLE_PHONE_SIGNUP"
    CHANGES=$((CHANGES+1))
fi

if [ "$(get_env_value ENABLE_PHONE_AUTOCONFIRM)" != "$ENABLE_PHONE_AUTOCONFIRM" ]; then
    echo "${C_YELLOW}ENABLE_PHONE_AUTOCONFIRM${C_RESET}"
    echo "  Before: $(get_env_value ENABLE_PHONE_AUTOCONFIRM)"
    echo "  After:  $ENABLE_PHONE_AUTOCONFIRM"
    CHANGES=$((CHANGES+1))
fi

if [ "$(get_env_value TWILIO_ACCOUNT_SID)" != "$TWILIO_ACCOUNT_SID" ]; then
    echo "${C_YELLOW}TWILIO_ACCOUNT_SID${C_RESET}"
    echo "  Before: $(get_env_value TWILIO_ACCOUNT_SID | sed 's/./*/g')"
    echo "  After:  ${TWILIO_ACCOUNT_SID:0:10}..."
    CHANGES=$((CHANGES+1))
fi

if [ "$(get_env_value TWILIO_AUTH_TOKEN)" != "$TWILIO_AUTH_TOKEN" ]; then
    echo "${C_YELLOW}TWILIO_AUTH_TOKEN${C_RESET}"
    echo "  Before: $(get_env_value TWILIO_AUTH_TOKEN | sed 's/./*/g')"
    echo "  After:  [REDACTED]"
    CHANGES=$((CHANGES+1))
fi

if [ "$(get_env_value TWILIO_PHONE_NUMBER)" != "$TWILIO_PHONE_NUMBER" ]; then
    echo "${C_YELLOW}TWILIO_PHONE_NUMBER${C_RESET}"
    echo "  Before: $(get_env_value TWILIO_PHONE_NUMBER)"
    echo "  After:  $TWILIO_PHONE_NUMBER"
    CHANGES=$((CHANGES+1))
fi

if [ $CHANGES -eq 0 ]; then
    echo "${C_GREEN}No changes detected${C_RESET}"
    echo
    print_info "Exiting without making changes"
    exit 0
fi

echo
printf "${C_CYAN}Total changes: %d${C_RESET}\n" "$CHANGES"
echo

if [[ $(ask_yn "Apply these changes?" "n") = "n" ]]; then
    print_warning "Changes cancelled by user"
    exit 0
fi

print_section "APPLYING CHANGES"

# Create backup
BACKUP_FILE="/srv/supabase/.env.backup.$(date +%Y%m%d-%H%M%S)"
cp /srv/supabase/.env "$BACKUP_FILE"
print_success "Backup created: $BACKUP_FILE"
echo

# Update all values
print_info "Updating configuration file..."

update_env_value "SITE_URL" "$SITE_URL"
update_env_value "API_EXTERNAL_URL" "$API_EXTERNAL_URL"
update_env_value "SUPABASE_PUBLIC_URL" "${SUPABASE_PUBLIC_URL:-$API_EXTERNAL_URL}"
update_env_value "ADDITIONAL_REDIRECT_URLS" "$ADDITIONAL_REDIRECT_URLS"
update_env_value "JWT_SECRET" "$JWT_SECRET"
update_env_value "JWT_EXPIRY" "$JWT_EXPIRY"
update_env_value "ANON_KEY" "$ANON_KEY"
update_env_value "SERVICE_ROLE_KEY" "$SERVICE_ROLE_KEY"
update_env_value "SMTP_HOST" "$SMTP_HOST"
update_env_value "SMTP_PORT" "$SMTP_PORT"
update_env_value "SMTP_USER" "$SMTP_USER"
update_env_value "SMTP_ADMIN_EMAIL" "$SMTP_ADMIN_EMAIL"
update_env_value "SMTP_SENDER_NAME" "$SMTP_SENDER_NAME"
update_env_value "ENABLE_EMAIL_SIGNUP" "$ENABLE_EMAIL_SIGNUP"
update_env_value "ENABLE_EMAIL_AUTOCONFIRM" "$ENABLE_EMAIL_AUTOCONFIRM"
update_env_value "ENABLE_PHONE_SIGNUP" "$ENABLE_PHONE_SIGNUP"
update_env_value "ENABLE_PHONE_AUTOCONFIRM" "$ENABLE_PHONE_AUTOCONFIRM"
update_env_value "ENABLE_ANONYMOUS_USERS" "$ENABLE_ANONYMOUS_USERS"
update_env_value "DISABLE_SIGNUP" "$DISABLE_SIGNUP"
update_env_value "TWILIO_ACCOUNT_SID" "$TWILIO_ACCOUNT_SID"
update_env_value "TWILIO_AUTH_TOKEN" "$TWILIO_AUTH_TOKEN"
update_env_value "TWILIO_PHONE_NUMBER" "$TWILIO_PHONE_NUMBER"
update_env_value "DASHBOARD_USERNAME" "$DASHBOARD_USERNAME"
update_env_value "STUDIO_DEFAULT_ORGANIZATION" "$STUDIO_DEFAULT_ORGANIZATION"
update_env_value "STUDIO_DEFAULT_PROJECT" "$STUDIO_DEFAULT_PROJECT"
update_env_value "POSTGRES_HOST" "$POSTGRES_HOST"
update_env_value "POSTGRES_DB" "$POSTGRES_DB"
update_env_value "POSTGRES_PORT" "$POSTGRES_PORT"
update_env_value "PGRST_DB_SCHEMAS" "$PGRST_DB_SCHEMAS"
update_env_value "POOLER_TENANT_ID" "$POOLER_TENANT_ID"

print_success "Configuration updated"
echo

print_info "Restarting Docker containers to apply changes..."
cd /srv/supabase || exit 1

print_info "Stopping containers..."
docker compose down >> /dev/null 2>&1

print_info "Waiting a moment..."
sleep 3

print_info "Starting containers with new configuration..."
docker compose up -d >> /dev/null 2>&1

print_info "Waiting for services to stabilize..."
sleep 10

print_info "Checking service health..."
echo

docker compose ps

echo
print_success "✓ Configuration updated and services restarted!"
echo
print_info "All containers should be 'Up' and 'healthy'"
print_info "Changes have been applied to your Supabase instance"
echo

