#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Supabase Local Setup Configuration Wizard    ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}\n"

# Check for yq
if ! command -v yq &> /dev/null; then
    echo -e "${YELLOW}⚠️  yq not found. Installing yq...${NC}"
    
    # Detect OS and architecture
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        armv7l) ARCH="arm" ;;
    esac
    
    YQ_VERSION="v4.40.5"
    YQ_BINARY="yq_${OS}_${ARCH}"
    
    echo -e "${BLUE}Downloading yq ${YQ_VERSION} for ${OS}_${ARCH}...${NC}"
    
    if curl -L "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}" -o /tmp/yq; then
        chmod +x /tmp/yq
        if sudo mv /tmp/yq /usr/local/bin/yq 2>/dev/null; then
            echo -e "${GREEN}✓ yq installed to /usr/local/bin/yq${NC}"
        else
            echo -e "${YELLOW}⚠️  Could not install to /usr/local/bin, using local copy${NC}"
            mv /tmp/yq ./yq
            export PATH="$PWD:$PATH"
        fi
    else
        echo -e "${RED}Failed to download yq. Please install manually:${NC}"
        echo -e "  https://github.com/mikefarah/yq#install"
        exit 1
    fi
    echo ""
fi

# Backup existing files with timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
if [ -f .env ]; then
    BACKUP_ENV=".env.backup.${TIMESTAMP}"
    echo -e "${YELLOW}📦 Backing up .env to ${BACKUP_ENV}${NC}"
    cp .env "$BACKUP_ENV"
fi

if [ -f docker-compose.yml ]; then
    BACKUP_COMPOSE="docker-compose.yml.backup.${TIMESTAMP}"
    echo -e "${YELLOW}📦 Backing up docker-compose.yml to ${BACKUP_COMPOSE}${NC}"
    cp docker-compose.yml "$BACKUP_COMPOSE"
fi

echo ""

# Function to generate secure random string
generate_secret() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-${1:-32}
}

# Function to validate URL
validate_url() {
    if [[ $1 =~ ^https?:// ]]; then
        return 0
    else
        return 1
    fi
}

# Function to validate email
validate_email() {
    if [[ $1 =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to validate port
validate_port() {
    if [[ $1 =~ ^[0-9]+$ ]] && [ $1 -ge 1 ] && [ $1 -le 65535 ]; then
        return 0
    else
        return 1
    fi
}

# Function to ask yes/no question
ask_yes_no() {
    local prompt="$1"
    local default="$2"
    local response
    
    if [ "$default" = "true" ]; then
        read -p "$prompt [Y/n]: " response
        response=${response:-Y}
    else
        read -p "$prompt [y/N]: " response
        response=${response:-N}
    fi
    
    if [[ "$response" =~ ^[Yy] ]]; then
        echo "true"
    else
        echo "false"
    fi
}

# Function to disable service in docker-compose.yml using yq
disable_service() {
    local service_name=$1
    local compose_file=$2
    
    echo -e "${YELLOW}  - Disabling ${service_name}${NC}"
    
    # Check if service exists
    if yq eval ".services.${service_name}" "$compose_file" | grep -q "null"; then
        echo -e "${YELLOW}    Service ${service_name} not found, skipping${NC}"
        return
    fi
    
    # Delete the service
    yq eval "del(.services.${service_name})" -i "$compose_file"
    
    # Remove dependencies on this service from all other services
    yq eval "del(.services.[].depends_on.${service_name})" -i "$compose_file"
}

# Auto-detect local IP
LOCAL_IP=$(ip route get 1 | awk '{print $7;exit}' 2>/dev/null || echo "localhost")
echo -e "${GREEN}🌐 Auto-detected local IP: ${LOCAL_IP}${NC}\n"

# ============================================================================
# FEATURE SELECTION
# ============================================================================
echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         STEP 1: FEATURE SELECTION              ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}\n"

ENABLE_ANALYTICS=$(ask_yes_no "Enable Analytics/Logs? (requires 2GB+ RAM)" "false")
ENABLE_EMAIL_AUTH=$(ask_yes_no "Enable Email Authentication?" "true")
ENABLE_PHONE_AUTH=$(ask_yes_no "Enable Phone Authentication?" "false")
ENABLE_ANONYMOUS=$(ask_yes_no "Enable Anonymous Users?" "false")
ENABLE_STORAGE=$(ask_yes_no "Enable Storage (file uploads)?" "true")
ENABLE_REALTIME=$(ask_yes_no "Enable Realtime?" "true")
ENABLE_FUNCTIONS=$(ask_yes_no "Enable Edge Functions?" "true")

# ============================================================================
# GENERATE SECRETS
# ============================================================================
echo -e "\n${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         STEP 2: GENERATING SECRETS             ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}\n"

echo -e "${GREEN}🔐 Generating crypto-secure secrets...${NC}"
POSTGRES_PASSWORD=$(generate_secret 32)
JWT_SECRET=$(generate_secret 32)
SECRET_KEY_BASE=$(generate_secret 64)
VAULT_ENC_KEY=$(generate_secret 32)
PG_META_CRYPTO_KEY=$(generate_secret 32)
LOGFLARE_PUBLIC=$(generate_secret 32)
LOGFLARE_PRIVATE=$(generate_secret 32)
DASHBOARD_PASSWORD=$(generate_secret 16)

# ============================================================================
# DATABASE CONFIGURATION
# ============================================================================
echo -e "\n${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         STEP 3: DATABASE CONFIG                ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}\n"

read -p "PostgreSQL Host [db]: " POSTGRES_HOST
POSTGRES_HOST=${POSTGRES_HOST:-db}

read -p "PostgreSQL Database [postgres]: " POSTGRES_DB
POSTGRES_DB=${POSTGRES_DB:-postgres}

read -p "PostgreSQL Port [5432]: " POSTGRES_PORT
POSTGRES_PORT=${POSTGRES_PORT:-5432}
while ! validate_port "$POSTGRES_PORT"; do
    echo -e "${RED}Invalid port number${NC}"
    read -p "PostgreSQL Port: " POSTGRES_PORT
done

# ============================================================================
# API GATEWAY CONFIGURATION
# ============================================================================
echo -e "\n${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         STEP 4: API GATEWAY CONFIG             ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}\n"

read -p "Kong HTTP Port [8000]: " KONG_HTTP_PORT
KONG_HTTP_PORT=${KONG_HTTP_PORT:-8000}
while ! validate_port "$KONG_HTTP_PORT"; do
    echo -e "${RED}Invalid port number${NC}"
    read -p "Kong HTTP Port: " KONG_HTTP_PORT
done

read -p "Kong HTTPS Port [8443]: " KONG_HTTPS_PORT
KONG_HTTPS_PORT=${KONG_HTTPS_PORT:-8443}
while ! validate_port "$KONG_HTTPS_PORT"; do
    echo -e "${RED}Invalid port number${NC}"
    read -p "Kong HTTPS Port: " KONG_HTTPS_PORT
done

# ============================================================================
# APPLICATION URLs
# ============================================================================
echo -e "\n${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         STEP 5: APPLICATION URLS               ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}\n"

read -p "Frontend URL (SITE_URL) [http://${LOCAL_IP}:3000]: " SITE_URL
SITE_URL=${SITE_URL:-http://${LOCAL_IP}:3000}
while ! validate_url "$SITE_URL"; do
    echo -e "${RED}Invalid URL format${NC}"
    read -p "SITE_URL: " SITE_URL
done

read -p "Supabase API URL (API_EXTERNAL_URL) [http://${LOCAL_IP}:${KONG_HTTP_PORT}]: " API_EXTERNAL_URL
API_EXTERNAL_URL=${API_EXTERNAL_URL:-http://${LOCAL_IP}:${KONG_HTTP_PORT}}
while ! validate_url "$API_EXTERNAL_URL"; do
    echo -e "${RED}Invalid URL format${NC}"
    read -p "API_EXTERNAL_URL: " API_EXTERNAL_URL
done

SUPABASE_PUBLIC_URL=$API_EXTERNAL_URL

read -p "Additional redirect URLs (comma-separated, optional): " ADDITIONAL_REDIRECT_URLS

# ============================================================================
# EMAIL AUTH CONFIGURATION
# ============================================================================
if [ "$ENABLE_EMAIL_AUTH" = "true" ]; then
    echo -e "\n${BLUE}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║         STEP 6: EMAIL AUTH CONFIG              ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}\n"
    
    ENABLE_EMAIL_SIGNUP="true"
    DISABLE_SIGNUP="false"
    
    ENABLE_EMAIL_AUTOCONFIRM=$(ask_yes_no "Auto-confirm email signups? (dev only)" "false")
    
    USE_RESEND=$(ask_yes_no "Use Resend for email delivery?" "false")
    
    if [ "$USE_RESEND" = "true" ]; then
        echo -e "\n${YELLOW}📧 Configure Resend SMTP${NC}"
        echo -e "Get your credentials from: https://resend.com/emails"
        
        read -p "Resend SMTP Host [smtp.resend.com]: " SMTP_HOST
        SMTP_HOST=${SMTP_HOST:-smtp.resend.com}
        
        read -p "Resend SMTP Port [465 or 587]: " SMTP_PORT
        SMTP_PORT=${SMTP_PORT:-465}
        
        read -p "Resend API Key (starts with re_): " SMTP_PASS
        
        read -p "From Email Address: " SMTP_ADMIN_EMAIL
        while ! validate_email "$SMTP_ADMIN_EMAIL"; do
            echo -e "${RED}Invalid email format${NC}"
            read -p "From Email Address: " SMTP_ADMIN_EMAIL
        done
        
        SMTP_USER="resend"
        SMTP_SENDER_NAME="Supabase Auth"
    else
        echo -e "${YELLOW}Using local mail server (emails won't be delivered)${NC}"
        SMTP_HOST="supabase-mail"
        SMTP_PORT="2500"
        SMTP_USER="fake_mail_user"
        SMTP_PASS="fake_mail_password"
        SMTP_ADMIN_EMAIL="admin@example.com"
        SMTP_SENDER_NAME="fake_sender"
    fi
else
    ENABLE_EMAIL_SIGNUP="false"
    DISABLE_SIGNUP="true"
    ENABLE_EMAIL_AUTOCONFIRM="false"
    SMTP_HOST="supabase-mail"
    SMTP_PORT="2500"
    SMTP_USER="fake_mail_user"
    SMTP_PASS="fake_mail_password"
    SMTP_ADMIN_EMAIL="admin@example.com"
    SMTP_SENDER_NAME="fake_sender"
fi

# ============================================================================
# PHONE AUTH CONFIGURATION
# ============================================================================
if [ "$ENABLE_PHONE_AUTH" = "true" ]; then
    echo -e "\n${BLUE}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║         STEP 7: PHONE AUTH CONFIG              ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}\n"
    
    ENABLE_PHONE_SIGNUP="true"
    ENABLE_PHONE_AUTOCONFIRM=$(ask_yes_no "Auto-confirm phone signups? (dev only)" "true")
else
    ENABLE_PHONE_SIGNUP="false"
    ENABLE_PHONE_AUTOCONFIRM="false"
fi

# ============================================================================
# STUDIO CONFIGURATION
# ============================================================================
echo -e "\n${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         STEP 8: STUDIO CONFIG                  ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}\n"

read -p "Dashboard Username [supabase]: " DASHBOARD_USERNAME
DASHBOARD_USERNAME=${DASHBOARD_USERNAME:-supabase}

read -p "Studio Default Organization [Default Organization]: " STUDIO_DEFAULT_ORGANIZATION
STUDIO_DEFAULT_ORGANIZATION=${STUDIO_DEFAULT_ORGANIZATION:-Default Organization}

read -p "Studio Default Project [Default Project]: " STUDIO_DEFAULT_PROJECT
STUDIO_DEFAULT_PROJECT=${STUDIO_DEFAULT_PROJECT:-Default Project}

USE_OPENAI=$(ask_yes_no "Enable SQL Editor AI Assistant? (requires OpenAI API key)" "false")
if [ "$USE_OPENAI" = "true" ]; then
    read -p "OpenAI API Key: " OPENAI_API_KEY
else
    OPENAI_API_KEY=""
fi

# ============================================================================
# ADDITIONAL CONFIGURATION
# ============================================================================
echo -e "\n${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         STEP 9: ADDITIONAL CONFIG              ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}\n"

read -p "JWT Expiry (seconds) [3600]: " JWT_EXPIRY
JWT_EXPIRY=${JWT_EXPIRY:-3600}

read -p "PostgREST DB Schemas [public,storage,graphql_public]: " PGRST_DB_SCHEMAS
PGRST_DB_SCHEMAS=${PGRST_DB_SCHEMAS:-public,storage,graphql_public}

if [ "$ENABLE_FUNCTIONS" = "true" ]; then
    FUNCTIONS_VERIFY_JWT=$(ask_yes_no "Verify JWT for Edge Functions?" "false")
else
    FUNCTIONS_VERIFY_JWT="false"
fi

read -p "Docker socket location [/var/run/docker.sock]: " DOCKER_SOCKET_LOCATION
DOCKER_SOCKET_LOCATION=${DOCKER_SOCKET_LOCATION:-/var/run/docker.sock}

IMGPROXY_ENABLE_WEBP_DETECTION="true"

# Connection pooler config
POOLER_PROXY_PORT_TRANSACTION="6543"
POOLER_DEFAULT_POOL_SIZE="20"
POOLER_MAX_CLIENT_CONN="100"
read -p "Pooler Tenant ID [supabase-local]: " POOLER_TENANT_ID
POOLER_TENANT_ID=${POOLER_TENANT_ID:-supabase-local}
POOLER_DB_POOL_SIZE="5"

# ============================================================================
# GENERATE JWT KEYS
# ============================================================================
echo -e "\n${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         STEP 10: JWT KEY GENERATION            ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}\n"

echo -e "${YELLOW}⚠️  You need to generate ANON_KEY and SERVICE_ROLE_KEY${NC}"
echo -e "${YELLOW}    These are JWT tokens signed with your JWT_SECRET${NC}\n"
echo -e "${GREEN}Your JWT_SECRET is:${NC} ${JWT_SECRET}\n"
echo -e "${YELLOW}Opening Supabase JWT generation documentation...${NC}\n"

# Try to open browser
if command -v xdg-open &> /dev/null; then
    xdg-open "https://supabase.com/docs/guides/self-hosting/docker#api-keys" &> /dev/null &
elif command -v open &> /dev/null; then
    open "https://supabase.com/docs/guides/self-hosting/docker#api-keys" &> /dev/null &
else
    echo -e "${RED}Could not open browser automatically${NC}"
    echo -e "Please visit: https://supabase.com/docs/guides/self-hosting/docker#api-keys"
fi

echo -e "\n${YELLOW}Instructions:${NC}"
echo -e "1. Use the link above or visit: https://supabase.com/docs/guides/self-hosting/docker#api-keys"
echo -e "2. Generate two JWT tokens with your JWT_SECRET"
echo -e "3. ANON_KEY: role='anon'"
echo -e "4. SERVICE_ROLE_KEY: role='service_role'"
echo -e "5. Copy and paste them below\n"

read -p "Press ENTER when ready to input JWT keys..."

read -p "ANON_KEY: " ANON_KEY
while [ -z "$ANON_KEY" ]; do
    echo -e "${RED}ANON_KEY cannot be empty${NC}"
    read -p "ANON_KEY: " ANON_KEY
done

read -p "SERVICE_ROLE_KEY: " SERVICE_ROLE_KEY
while [ -z "$SERVICE_ROLE_KEY" ]; do
    echo -e "${RED}SERVICE_ROLE_KEY cannot be empty${NC}"
    read -p "SERVICE_ROLE_KEY: " SERVICE_ROLE_KEY
done

# ============================================================================
# GENERATE .ENV FILE
# ============================================================================
echo -e "\n${GREEN}📝 Generating .env file...${NC}"

cat > .env << EOF
############
# Secrets
# GENERATED: $(date)
############

POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
JWT_SECRET=${JWT_SECRET}
ANON_KEY=${ANON_KEY}
SERVICE_ROLE_KEY=${SERVICE_ROLE_KEY}
DASHBOARD_USERNAME=${DASHBOARD_USERNAME}
DASHBOARD_PASSWORD=${DASHBOARD_PASSWORD}
SECRET_KEY_BASE=${SECRET_KEY_BASE}
VAULT_ENC_KEY=${VAULT_ENC_KEY}
PG_META_CRYPTO_KEY=${PG_META_CRYPTO_KEY}


############
# Database
############

POSTGRES_HOST=${POSTGRES_HOST}
POSTGRES_DB=${POSTGRES_DB}
POSTGRES_PORT=${POSTGRES_PORT}


############
# Supavisor -- Database pooler
############

POOLER_PROXY_PORT_TRANSACTION=${POOLER_PROXY_PORT_TRANSACTION}
POOLER_DEFAULT_POOL_SIZE=${POOLER_DEFAULT_POOL_SIZE}
POOLER_MAX_CLIENT_CONN=${POOLER_MAX_CLIENT_CONN}
POOLER_TENANT_ID=${POOLER_TENANT_ID}
POOLER_DB_POOL_SIZE=${POOLER_DB_POOL_SIZE}


############
# API Proxy - Kong
############

KONG_HTTP_PORT=${KONG_HTTP_PORT}
KONG_HTTPS_PORT=${KONG_HTTPS_PORT}


############
# API - PostgREST
############

PGRST_DB_SCHEMAS=${PGRST_DB_SCHEMAS}


############
# Auth - GoTrue
############

SITE_URL=${SITE_URL}
ADDITIONAL_REDIRECT_URLS=${ADDITIONAL_REDIRECT_URLS}
JWT_EXPIRY=${JWT_EXPIRY}
DISABLE_SIGNUP=${DISABLE_SIGNUP}
API_EXTERNAL_URL=${API_EXTERNAL_URL}

## Mailer Config
MAILER_URLPATHS_CONFIRMATION="/auth/v1/verify"
MAILER_URLPATHS_INVITE="/auth/v1/verify"
MAILER_URLPATHS_RECOVERY="/auth/v1/verify"
MAILER_URLPATHS_EMAIL_CHANGE="/auth/v1/verify"

## Email auth
ENABLE_EMAIL_SIGNUP=${ENABLE_EMAIL_SIGNUP}
ENABLE_EMAIL_AUTOCONFIRM=${ENABLE_EMAIL_AUTOCONFIRM}
SMTP_ADMIN_EMAIL=${SMTP_ADMIN_EMAIL}
SMTP_HOST=${SMTP_HOST}
SMTP_PORT=${SMTP_PORT}
SMTP_USER=${SMTP_USER}
SMTP_PASS=${SMTP_PASS}
SMTP_SENDER_NAME=${SMTP_SENDER_NAME}
ENABLE_ANONYMOUS_USERS=${ENABLE_ANONYMOUS}

## Phone auth
ENABLE_PHONE_SIGNUP=${ENABLE_PHONE_SIGNUP}
ENABLE_PHONE_AUTOCONFIRM=${ENABLE_PHONE_AUTOCONFIRM}


############
# Studio
############

STUDIO_DEFAULT_ORGANIZATION=${STUDIO_DEFAULT_ORGANIZATION}
STUDIO_DEFAULT_PROJECT=${STUDIO_DEFAULT_PROJECT}
SUPABASE_PUBLIC_URL=${SUPABASE_PUBLIC_URL}
IMGPROXY_ENABLE_WEBP_DETECTION=${IMGPROXY_ENABLE_WEBP_DETECTION}
OPENAI_API_KEY=${OPENAI_API_KEY}


############
# Functions
############

FUNCTIONS_VERIFY_JWT=${FUNCTIONS_VERIFY_JWT}


############
# Logs - Analytics
############

LOGFLARE_PUBLIC_ACCESS_TOKEN=${LOGFLARE_PUBLIC}
LOGFLARE_PRIVATE_ACCESS_TOKEN=${LOGFLARE_PRIVATE}
DOCKER_SOCKET_LOCATION=${DOCKER_SOCKET_LOCATION}

# Google Cloud (not configured)
GOOGLE_PROJECT_ID=GOOGLE_PROJECT_ID
GOOGLE_PROJECT_NUMBER=GOOGLE_PROJECT_NUMBER
EOF

echo -e "${GREEN}✓ .env file generated${NC}"

# ============================================================================
# MODIFY DOCKER-COMPOSE.YML
# ============================================================================
echo -e "${GREEN}📝 Modifying docker-compose.yml using yq...${NC}"

# Check if docker-compose.yml exists
if [ ! -f docker-compose.yml ]; then
    echo -e "${RED}Error: docker-compose.yml not found${NC}"
    exit 1
fi

# Create a working copy
cp docker-compose.yml docker-compose.yml.work

# Disable services based on feature selection
if [ "$ENABLE_ANALYTICS" = "false" ]; then
    disable_service "analytics" "docker-compose.yml.work"
fi

if [ "$ENABLE_STORAGE" = "false" ]; then
    disable_service "storage" "docker-compose.yml.work"
    disable_service "imgproxy" "docker-compose.yml.work"
fi

if [ "$ENABLE_REALTIME" = "false" ]; then
    disable_service "realtime" "docker-compose.yml.work"
fi

if [ "$ENABLE_FUNCTIONS" = "false" ]; then
    disable_service "functions" "docker-compose.yml.work"
fi

# Move working copy to final
mv docker-compose.yml.work docker-compose.yml

echo -e "${GREEN}✓ docker-compose.yml modified${NC}"

# ============================================================================
# GENERATE SUMMARY
# ============================================================================
echo -e "\n${GREEN}📄 Generating configuration summary...${NC}"

cat > SETUP_SUMMARY.md << EOF
# Supabase Configuration Summary

**Generated:** $(date)

## 🔐 Credentials

### Dashboard Access
- **URL:** ${API_EXTERNAL_URL}
- **Username:** ${DASHBOARD_USERNAME}
- **Password:** ${DASHBOARD_PASSWORD}

### Database
- **Host:** ${POSTGRES_HOST}
- **Port:** ${POSTGRES_PORT}
- **Database:** ${POSTGRES_DB}
- **Password:** ${POSTGRES_PASSWORD}

### API Keys
- **JWT Secret:** ${JWT_SECRET}
- **ANON_KEY:** ${ANON_KEY}
- **SERVICE_ROLE_KEY:** ${SERVICE_ROLE_KEY}

## ✨ Enabled Features

EOF

if [ "$ENABLE_ANALYTICS" = "true" ]; then
    echo "- ✅ Analytics/Logs" >> SETUP_SUMMARY.md
else
    echo "- ❌ Analytics/Logs (disabled to save RAM)" >> SETUP_SUMMARY.md
fi

if [ "$ENABLE_EMAIL_AUTH" = "true" ]; then
    echo "- ✅ Email Authentication" >> SETUP_SUMMARY.md
    if [ "$USE_RESEND" = "true" ]; then
        echo "  - Using Resend SMTP (${SMTP_ADMIN_EMAIL})" >> SETUP_SUMMARY.md
    else
        echo "  - Using local mail server (emails won't be delivered)" >> SETUP_SUMMARY.md
    fi
else
    echo "- ❌ Email Authentication" >> SETUP_SUMMARY.md
fi

if [ "$ENABLE_PHONE_AUTH" = "true" ]; then
    echo "- ✅ Phone Authentication" >> SETUP_SUMMARY.md
else
    echo "- ❌ Phone Authentication" >> SETUP_SUMMARY.md
fi

if [ "$ENABLE_ANONYMOUS" = "true" ]; then
    echo "- ✅ Anonymous Users" >> SETUP_SUMMARY.md
else
    echo "- ❌ Anonymous Users" >> SETUP_SUMMARY.md
fi

if [ "$ENABLE_STORAGE" = "true" ]; then
    echo "- ✅ Storage (file uploads)" >> SETUP_SUMMARY.md
else
    echo "- ❌ Storage" >> SETUP_SUMMARY.md
fi

if [ "$ENABLE_REALTIME" = "true" ]; then
    echo "- ✅ Realtime" >> SETUP_SUMMARY.md
else
    echo "- ❌ Realtime" >> SETUP_SUMMARY.md
fi

if [ "$ENABLE_FUNCTIONS" = "true" ]; then
    echo "- ✅ Edge Functions" >> SETUP_SUMMARY.md
else
    echo "- ❌ Edge Functions" >> SETUP_SUMMARY.md
fi

cat >> SETUP_SUMMARY.md << EOF

## 🌐 URLs

- **Frontend:** ${SITE_URL}
- **API:** ${API_EXTERNAL_URL}
- **Studio Dashboard:** ${API_EXTERNAL_URL}

## 🚀 Next Steps

1. Start Supabase:
   \`\`\`bash
   docker compose up -d
   \`\`\`

2. Check service status:
   \`\`\`bash
   docker compose ps
   \`\`\`

3. View logs:
   \`\`\`bash
   docker compose logs -f
   \`\`\`

4. Access Studio Dashboard:
   - Open: ${API_EXTERNAL_URL}
   - Login with credentials above

## 🔒 Security Notes

- **IMPORTANT:** These credentials are for development only
- Change all passwords before production deployment
- Store credentials securely (use a password manager)
- Never commit .env files to version control

## 📦 Backups Created

EOF

if [ -f "$BACKUP_ENV" ]; then
    echo "- .env: ${BACKUP_ENV}" >> SETUP_SUMMARY.md
fi

if [ -f "$BACKUP_COMPOSE" ]; then
    echo "- docker-compose.yml: ${BACKUP_COMPOSE}" >> SETUP_SUMMARY.md
fi

cat >> SETUP_SUMMARY.md << EOF

## 📚 Documentation

- [Supabase Docs](https://supabase.com/docs)
- [Self-Hosting Guide](https://supabase.com/docs/guides/self-hosting)
- [API Reference](https://supabase.com/docs/reference)
EOF

echo -e "${GREEN}✓ Summary saved to SETUP_SUMMARY.md${NC}"

# ============================================================================
# FINAL OUTPUT
# ============================================================================
echo -e "\n${GREEN}╔════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              SETUP COMPLETE! 🎉                 ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}\n"

echo -e "${YELLOW}📋 Configuration files generated:${NC}"
echo -e "   - .env"
echo -e "   - docker-compose.yml (modified)"
echo -e "   - SETUP_SUMMARY.md"
echo ""
echo -e "${YELLOW}📦 Backups created:${NC}"
[ -f "$BACKUP_ENV" ] && echo -e "   - ${BACKUP_ENV}"
[ -f "$BACKUP_COMPOSE" ] && echo -e "   - ${BACKUP_COMPOSE}"
echo ""
echo -e "${GREEN}🚀 To start Supabase:${NC}"
echo -e "   ${BLUE}docker compose up -d${NC}"
echo ""
echo -e "${GREEN}🔐 Dashboard credentials:${NC}"
echo -e "   URL:      ${API_EXTERNAL_URL}"
echo -e "   Username: ${DASHBOARD_USERNAME}"
echo -e "   Password: ${DASHBOARD_PASSWORD}"
echo ""
echo -e "${YELLOW}📖 See SETUP_SUMMARY.md for complete configuration details${NC}"
echo ""