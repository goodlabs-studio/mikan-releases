#!/bin/bash
# Mikan Installation Script
# Usage: curl -o- https://raw.githubusercontent.com/.../install.sh | bash

set -e

# Configuration
DISTRIBUTION_URL="https://mikan-public.s3.amazonaws.com/distribution/staging.zip"
ECR_REGISTRY="624622221797.dkr.ecr.us-east-1.amazonaws.com"
INSTALL_DIR="mikan-distribution"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_header() {
    echo ""
    echo "Mikan Installation Script"
    echo "========================="
    echo ""
}

print_ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

check_command() {
    if command -v "$1" &> /dev/null; then
        print_ok "$2 installed"
        return 0
    else
        print_error "$2 is not installed. Please install it first."
        return 1
    fi
}

check_prerequisites() {
    echo "Checking prerequisites..."
    local failed=0

    check_command "docker" "Docker" || failed=1
    check_command "curl" "curl" || failed=1
    check_command "unzip" "unzip" || failed=1

    # Check Docker Compose (both v1 and v2)
    if command -v "docker-compose" &> /dev/null || docker compose version &> /dev/null; then
        print_ok "Docker Compose installed"
    else
        print_error "Docker Compose is not installed. Please install it first."
        failed=1
    fi

    # Check if Docker daemon is running
    if docker info &> /dev/null; then
        print_ok "Docker daemon is running"
    else
        print_error "Docker daemon is not running. Please start Docker first."
        failed=1
    fi

    if [ $failed -eq 1 ]; then
        echo ""
        print_error "Prerequisites check failed. Please install missing dependencies."
        exit 1
    fi

    echo ""
}

download_distribution() {
    echo "Downloading Mikan distribution..."

    # Check if directory already exists
    if [ -d "$INSTALL_DIR" ]; then
        print_warn "Directory '$INSTALL_DIR' already exists."
        read -p "Do you want to overwrite it? (y/N): " overwrite < /dev/tty
        if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
            echo "Installation cancelled."
            exit 0
        fi
        rm -rf "$INSTALL_DIR"
    fi

    # Download and extract
    curl -sL -o staging.zip "$DISTRIBUTION_URL"
    unzip -q staging.zip
    rm staging.zip

    print_ok "Downloaded and extracted to ./$INSTALL_DIR"
    echo ""
}

get_user_input() {
    echo "Configuration"
    echo "-------------"
    echo ""

    # Redirect input from terminal (needed when running via pipe)
    exec < /dev/tty

    # Step 1: ECR Token (먼저 받아서 Docker login 검증)
    echo "Step 1: ECR Token (Docker Image Access)"
    echo ""
    echo "  Enter the ECR Token provided by the Mikan team."
    echo "  (Contact mikan@goodlabs.studio if you don't have a token)"
    echo ""
    while [ -z "$ECR_TOKEN" ]; do
        # Increase line buffer for long token input
        if command -v stty &> /dev/null; then
            stty -icanon 2>/dev/null || true
        fi
        echo -n "  Enter ECR Token: "
        ECR_TOKEN=$(head -n 1)
        if command -v stty &> /dev/null; then
            stty icanon 2>/dev/null || true
        fi
        # Clean up the token (remove whitespace and newlines)
        ECR_TOKEN=$(echo "$ECR_TOKEN" | tr -d '\n\r ')
        if [ -z "$ECR_TOKEN" ]; then
            print_error "ECR Token is required."
        fi
    done
    print_ok "ECR Token received (${#ECR_TOKEN} characters)"

    # Docker login 즉시 검증
    echo ""
    echo "Verifying Docker credentials..."
    docker_login

    # Step 2: Confluent API credentials
    echo ""
    echo "Step 2: Confluent Cloud API Credentials"
    echo ""
    echo "  To create Confluent API credentials:"
    echo ""
    echo "  [Create Service Account]"
    echo "  1. Go to Confluent Cloud: https://confluent.cloud"
    echo "  2. Navigate to: Administration > Accounts and access"
    echo "  3. Go to 'Service accounts' tab > Click 'Add service account'"
    echo "  4. Enter name (e.g., 'mikan') and description, click 'Next'"
    echo ""
    echo "  [Assign Permissions - click 'Add role assignment' for each]"
    echo "  5. Select Organization > Role: BillingAdmin"
    echo "  6. For each cluster: Select Cluster > Role: CloudClusterAdmin"
    echo "  7. Click 'Review and create' - verify Access looks like:"
    echo "       BillingAdmin        -> Your Organization"
    echo "       CloudClusterAdmin   -> cluster-1 (lkc-xxxxx)"
    echo "       CloudClusterAdmin   -> cluster-2 (lkc-xxxxx)"
    echo "  8. Click 'Create'"
    echo ""
    echo "  [Create API Key]"
    echo "  9. Navigate to: Administration > API keys"
    echo "  10. Click 'Add API key' > Select the service account created above"
    echo "  11. Set scope to 'Cloud resource management'"
    echo "  12. Copy the generated Key and Secret"
    echo ""

    # Confluent API Key
    while [ -z "$CONFLUENT_KEY" ]; do
        read -p "  Enter CONFLUENT_MANAGEMENT_API_KEY: " CONFLUENT_KEY
        if [ -z "$CONFLUENT_KEY" ]; then
            print_error "CONFLUENT_MANAGEMENT_API_KEY is required."
        fi
    done

    # Confluent API Secret
    while [ -z "$CONFLUENT_SECRET" ]; do
        read -p "  Enter CONFLUENT_MANAGEMENT_API_SECRET: " CONFLUENT_SECRET
        if [ -z "$CONFLUENT_SECRET" ]; then
            print_error "CONFLUENT_MANAGEMENT_API_SECRET is required."
        fi
    done

    # Step 3: Encryption Key (optional)
    echo ""
    echo "Step 3: Encryption Key (Optional)"
    echo ""
    echo "  Enter an existing 64-character ENCRYPTION_KEY if you have one (e.g., from a previous installation)."
    echo "  Leave blank to auto-generate a new 64-character key."
    echo ""
    read -p "  Enter ENCRYPTION_KEY (or press Enter to generate): " USER_ENCRYPTION_KEY

    # Step 4: Port Configuration (optional)
    echo ""
    echo "Step 4: Port Configuration (Optional)"
    echo ""
    read -p "  Enter API port [default: 3333]: " USER_API_PORT
    read -p "  Enter App port [default: 3000]: " USER_APP_PORT

    # Set defaults if not provided
    API_PORT="${USER_API_PORT:-3333}"
    APP_PORT="${USER_APP_PORT:-3000}"

    # Step 5: Service Selection
    echo ""
    select_services

    # Step 6: API_ENDPOINT (cron 선택 시에만)
    if [[ " ${SELECTED_SERVICES[*]} " =~ " cron " ]]; then
        echo ""
        echo "Step 6: Cron Service Configuration"
        echo ""
        echo "  API_ENDPOINT is the URL that the cron service will use to communicate with the API."
        echo "  Default is 'http://api:3333' for internal Docker network communication."
        echo ""
        read -p "  Enter API_ENDPOINT [default: http://api:3333]: " USER_API_ENDPOINT
        API_ENDPOINT="${USER_API_ENDPOINT:-http://api:3333}"
    else
        API_ENDPOINT="http://api:3333"
    fi

    echo ""
}

generate_encryption_key() {
    if [ -n "$USER_ENCRYPTION_KEY" ]; then
        ENCRYPTION_KEY="$USER_ENCRYPTION_KEY"
        print_ok "Using provided ENCRYPTION_KEY"
    else
        # Generate a 64-character random encryption key
        # Use 96 bytes to ensure enough characters remain after removing special chars
        ENCRYPTION_KEY=$(openssl rand -base64 96 | tr -dc 'a-zA-Z0-9' | head -c 64)
        print_ok "Generated new ENCRYPTION_KEY"
    fi
}

create_env_file() {
    cd "$INSTALL_DIR"

    cat > .env << EOF
# ===========================================
# Mikan Docker Compose Environment Variables
# ===========================================
# Generated by install.sh on $(date)

# -----------------
# Image Settings
# -----------------
IMAGE_TAG=staging

# -----------------
# Database Settings
# -----------------
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DB=mikan
DATABASE_SSL=false

# -----------------
# API Settings
# -----------------
NODE_ENV=production
PORT=${API_PORT}
CORS_ALLOWED_ORIGINS=http://localhost:${APP_PORT}

# -----------------
# Confluent Kafka
# -----------------
CONFLUENT_MANAGEMENT_API_KEY=${CONFLUENT_KEY}
CONFLUENT_MANAGEMENT_API_SECRET=${CONFLUENT_SECRET}

# -----------------
# Encryption
# -----------------
ENCRYPTION_KEY=${ENCRYPTION_KEY}

# -----------------
# Frontend App
# -----------------
APP_PORT=${APP_PORT}
REACT_APP_API_URL=http://localhost:${API_PORT}

# -----------------
# Data Storage
# -----------------
DATA_FOLDER=./data

# -----------------
# Cron Settings
# -----------------
API_ENDPOINT=${API_ENDPOINT}
KAFKA_CONSUMER_GROUPS_SCRIPT=/usr/bin/kafka-consumer-groups
CONSUMER_OFFSETS_SCRIPT=/app/consumer-offsets.sh
COLLECTION_INTERVAL=3600
CREDENTIALS_DIR=/app/credentials
EOF

    print_ok "Created .env file"
}

# Service selection menu
SERVICE_NAMES=("database" "api" "app" "cron")
SERVICE_DESCRIPTIONS=("PostgreSQL database" "Mikan API server" "Frontend application" "Consumer offset collector")
SELECTED_SERVICES=()

select_services() {
    echo "Step 5: Service Selection"
    echo ""
    echo "  Select which services to run."
    echo "  Use ↑↓ to move, Enter/Space to toggle, 'd' when done"
    echo ""

    # Initialize all services as selected
    local selected=(1 1 1 1)
    local current=0
    local num_services=${#SERVICE_NAMES[@]}

    # Hide cursor
    tput civis 2>/dev/null || true

    # Function to draw menu
    draw_menu() {
        # Move cursor up to redraw (only after first draw)
        if [ "$1" = "redraw" ]; then
            for ((i=0; i<num_services+1; i++)); do
                tput cuu1 2>/dev/null || echo -en "\033[1A"
            done
        fi

        for ((i=0; i<num_services; i++)); do
            local prefix="  "
            local checkbox="[ ]"

            if [ $i -eq $current ]; then
                prefix="> "
            fi

            if [ ${selected[$i]} -eq 1 ]; then
                checkbox="[x]"
            fi

            # Clear line and print
            tput el 2>/dev/null || true
            printf "  %s %s %-10s - %s\n" "$prefix" "$checkbox" "${SERVICE_NAMES[$i]}" "${SERVICE_DESCRIPTIONS[$i]}"
        done

        tput el 2>/dev/null || true
        echo ""
    }

    # Initial draw
    draw_menu "initial"

    # Read input
    while true; do
        # Read single character
        IFS= read -rsn1 key

        case "$key" in
            $'\x1b')  # Escape sequence (arrow keys)
                read -rsn2 key2
                case "$key2" in
                    '[A')  # Up arrow
                        ((current--))
                        if [ $current -lt 0 ]; then
                            current=$((num_services - 1))
                        fi
                        ;;
                    '[B')  # Down arrow
                        ((current++))
                        if [ $current -ge $num_services ]; then
                            current=0
                        fi
                        ;;
                esac
                draw_menu "redraw"
                ;;
            ''|' ')  # Enter or Space - toggle
                if [ ${selected[$current]} -eq 1 ]; then
                    selected[$current]=0
                else
                    selected[$current]=1
                fi
                draw_menu "redraw"
                ;;
            'd'|'D')  # Done
                break
                ;;
            'q'|'Q')  # Quit selection (keep defaults)
                break
                ;;
        esac
    done

    # Show cursor
    tput cnorm 2>/dev/null || true

    # Build selected services list
    SELECTED_SERVICES=()
    for ((i=0; i<num_services; i++)); do
        if [ ${selected[$i]} -eq 1 ]; then
            SELECTED_SERVICES+=("${SERVICE_NAMES[$i]}")
        fi
    done

    # Validate at least one service is selected
    if [ ${#SELECTED_SERVICES[@]} -eq 0 ]; then
        print_warn "No services selected. Selecting all services."
        SELECTED_SERVICES=("${SERVICE_NAMES[@]}")
    fi

    echo ""
    print_ok "Selected services: ${SELECTED_SERVICES[*]}"
}

docker_login() {
    echo ""
    echo "Logging in to Docker registry..."

    while true; do
        if echo "$ECR_TOKEN" | docker login --username AWS --password-stdin "$ECR_REGISTRY" &> /dev/null; then
            print_ok "Docker login successful"
            break
        else
            print_error "Docker login failed. Please check your ECR token."
            echo ""
            read -p "Do you want to re-enter the ECR token? (y/N): " retry < /dev/tty
            if [[ ! "$retry" =~ ^[Yy]$ ]]; then
                echo "Installation cancelled."
                exit 1
            fi
            echo ""
            echo -n "  Enter ECR Token: "
            if command -v stty &> /dev/null; then
                stty -icanon 2>/dev/null || true
            fi
            ECR_TOKEN=$(head -n 1 < /dev/tty)
            if command -v stty &> /dev/null; then
                stty icanon 2>/dev/null || true
            fi
            ECR_TOKEN=$(echo "$ECR_TOKEN" | tr -d '\n\r ')
            echo ""
        fi
    done
}

start_services() {
    local services="${SELECTED_SERVICES[*]}"

    echo ""
    echo "Pulling Docker images for: $services"
    echo ""
    if ! docker compose pull $services; then
        echo ""
        print_error "Failed to pull images. Please check your ECR token and try again."
        exit 1
    fi
    echo ""
    print_ok "Images pulled"

    echo ""
    echo "Starting services: $services"
    echo ""
    if ! docker compose up -d $services; then
        echo ""
        print_error "Failed to start services."
        exit 1
    fi
    echo ""
    print_ok "Services started"

    # Wait for services to be ready
    echo ""
    echo "Waiting for services to be ready..."
    sleep 10

    # Check service health
    if docker compose ps | grep -q "running"; then
        print_ok "All services are running"
    else
        print_warn "Some services may not be running. Check with: docker compose ps"
    fi
}

print_completion() {
    echo ""
    echo "========================================="
    echo "Installation complete!"
    echo "========================================="
    echo ""
    echo "Access Mikan at: http://localhost:${APP_PORT}"
    echo "API endpoint:    http://localhost:${API_PORT}"
    echo ""
    echo "Default credentials:"
    echo "  Email:    admin@mikan.local"
    echo "  Password: Admin123!"
    echo ""
    echo "(Please change your password on first login)"
    echo ""
    echo "-----------------------------------------"
    echo "IMPORTANT: Save this ENCRYPTION_KEY securely!"
    echo "You will need it if you reinstall or migrate."
    echo ""
    echo "  ENCRYPTION_KEY: ${ENCRYPTION_KEY}"
    echo ""
    echo "-----------------------------------------"
    echo ""
    echo "For Confluent charge back cluster API key settings"
    echo "and MongoDB configuration, please refer to the"
    echo "DEPLOYMENT.md file in the mikan-distribution folder."
    echo ""
}

# Main execution
main() {
    print_header
    check_prerequisites
    download_distribution
    get_user_input
    generate_encryption_key
    create_env_file
    start_services
    print_completion
}

main "$@"
