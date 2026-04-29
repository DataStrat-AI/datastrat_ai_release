#!/bin/bash
# =============================================================================
# DataStrat AI - Interactive Deployment Script
# =============================================================================

echo "==========================================================="
echo "        DataStrat AI - Enterprise Deployment Setup        "
echo "==========================================================="
echo ""

if [ -f ".env" ]; then
    read -p "A .env file already exists. Do you want to overwrite it? (y/N): " overwrite
    if [[ ! $overwrite =~ ^[Yy]$ ]]; then
        echo "Keeping existing .env file. Exiting setup."
        echo "To start the application, run: docker compose up -d"
        exit 0
    fi
fi

# Initialize standard `.env` variables from `.env.example`
cp .env.example .env

# --- Storage & Database Settings ---
echo ""
echo "--- Infrastructure Setup ---"
echo "You can either use the included local storage containers (Postgres, Redis, Qdrant, MinIO) OR connect to your own managed VPC infrastructure (AWS RDS, S3, etc.)."
read -p "Do you want to use the built-in local storage containers? (Y/n): " use_local_storage

if [[ $use_local_storage =~ ^[Nn]$ ]]; then
    # User is providing external managed services
    echo ""
    echo "[External Managed Infrastructure Mode]"
    
    # 1. Database
    read -p "PostgreSQL Host (e.g. rds.amazonaws.com): " db_host
    read -p "PostgreSQL Port [5432]: " db_port
    db_port=${db_port:-5432}
    read -p "PostgreSQL User [datastrat]: " db_user
    db_user=${db_user:-datastrat}
    read -sp "PostgreSQL Password: " db_pass
    echo ""
    read -p "PostgreSQL Database Name [datastrat]: " db_name
    db_name=${db_name:-datastrat}
    db_url="postgresql://${db_user}:${db_pass}@${db_host}:${db_port}/${db_name}"

    # 2. Redis
    read -p "Redis Host (e.g. cache.amazonaws.com): " redis_host
    read -p "Redis Port [6379]: " redis_port
    redis_port=${redis_port:-6379}
    redis_url="redis://${redis_host}:${redis_port}/0"

    # 3. Qdrant
    read -p "Qdrant Host (e.g. qdrant.your-cloud.com): " qdrant_host
    read -p "Qdrant Port [6333]: " qdrant_port
    qdrant_port=${qdrant_port:-6333}
    qdrant_url="http://${qdrant_host}:${qdrant_port}"
    
    # 4. Storage
    echo ""
    echo "[S3-Compatible Object Storage]"
    read -p "Storage Host (e.g. s3.amazonaws.com): " s3_host
    read -p "Storage Port [443]: " s3_port
    s3_port=${s3_port:-443}
    read -p "Storage Access Key: " s3_access
    read -p "Storage Secret Key: " s3_secret
    read -p "Storage Bucket Name: " s3_bucket
    
    if [ "$s3_port" = "443" ]; then
        s3_url="https://${s3_host}"
    else
        s3_url="http://${s3_host}:${s3_port}"
    fi

    # Replace values in .env
    sed -i.bak "s|^DB_HOST=.*|DB_HOST=${db_host}|g" .env
    sed -i.bak "s|^DB_PORT=.*|DB_PORT=${db_port}|g" .env
    sed -i.bak "s|^DB_USER=.*|DB_USER=${db_user}|g" .env
    sed -i.bak "s|^DB_PASS=.*|DB_PASS=${db_pass}|g" .env
    sed -i.bak "s|^DB_NAME=.*|DB_NAME=${db_name}|g" .env
    sed -i.bak "s|^DATABASE_URL=.*|DATABASE_URL=${db_url}|g" .env

    sed -i.bak "s|^REDIS_HOST=.*|REDIS_HOST=${redis_host}|g" .env
    sed -i.bak "s|^REDIS_PORT=.*|REDIS_PORT=${redis_port}|g" .env
    sed -i.bak "s|^REDIS_URL=.*|REDIS_URL=${redis_url}|g" .env

    sed -i.bak "s|^QDRANT_HOST=.*|QDRANT_HOST=${qdrant_host}|g" .env
    sed -i.bak "s|^QDRANT_PORT=.*|QDRANT_PORT=${qdrant_port}|g" .env
    sed -i.bak "s|^QDRANT_URL=.*|QDRANT_URL=${qdrant_url}|g" .env

    sed -i.bak "s|^STORAGE_HOST=.*|STORAGE_HOST=${s3_host}|g" .env
    sed -i.bak "s|^STORAGE_PORT=.*|STORAGE_PORT=${s3_port}|g" .env
    sed -i.bak "s|^STORAGE_ENDPOINT_URL=.*|STORAGE_ENDPOINT_URL=${s3_url}|g" .env
    sed -i.bak "s|^STORAGE_ACCESS_KEY=.*|STORAGE_ACCESS_KEY=${s3_access}|g" .env
    sed -i.bak "s|^STORAGE_SECRET_KEY=.*|STORAGE_SECRET_KEY=${s3_secret}|g" .env
    sed -i.bak "s|^STORAGE_BUCKET_NAME=.*|STORAGE_BUCKET_NAME=${s3_bucket}|g" .env
    
    # We leave COMPOSE_PROFILES empty so local storage containers don't start
    sed -i.bak "s|^COMPOSE_PROFILES=.*|COMPOSE_PROFILES=|g" .env
else
    # User is using local storage
    echo "Using default local storage containers."
    sed -i.bak "s|^COMPOSE_PROFILES=.*|COMPOSE_PROFILES=local-storage|g" .env
fi

# --- Domain & Routing Setup ---
echo ""
echo "--- Domain & Routing Setup ---"
read -p "Enter your main application domain (e.g., app.datastrat.ai or localhost): " app_domain
read -p "Enter your authentication domain for Zitadel (e.g., auth.datastrat.ai or localhost): " auth_domain

# Default to localhost if empty
app_domain=${app_domain:-localhost}
auth_domain=${auth_domain:-localhost}

# Prepare directories
mkdir -p nginx certs
touch nginx/headers.map nginx/ssl.conf

if [ "$app_domain" = "localhost" ]; then
    # Local development — always HTTP, direct ports
    app_url="http://localhost:3000"
    api_url="http://localhost:8000"
    auth_port="8080"
    auth_host="localhost:8080"
    auth_secure="false"
    z_public_url="http://localhost:8080"
    # No custom headers needed for localhost
    echo "" > nginx/headers.map
    echo "" > nginx/ssl.conf
else
    # Production domain — ask about SSL
    echo "Is SSL/HTTPS enabled for this deployment?"
    echo "1) Yes, handled by an External Load Balancer (Cloudflare, AWS ALB, Azure Gateway)"
    echo "2) Yes, handled by This Machine (Nginx)"
    echo "3) No (Plain HTTP)"
    read -p "Select option (1-3): " ssl_mode

    case $ssl_mode in
        1)
            # Mode: External SSL (SSL Offloading)
            app_url="https://${app_domain}"
            api_url="https://${app_domain}"
            auth_port="443"
            auth_host="${auth_domain}"
            auth_secure="true"
            z_public_url="https://${auth_domain}"
            
            # Force Zitadel to believe it's HTTPS regardless of port 80 traffic
            echo "map \$http_x_forwarded_proto \$pref_proto { default https; }" > nginx/headers.map
            echo "" > nginx/ssl.conf
            echo "Configured for External SSL (Port 80 to VM, HTTPS to User)."
            ;;
        2)
            # Mode: Local SSL (Nginx handles certs)
            app_url="https://${app_domain}"
            api_url="https://${app_domain}"
            auth_port="443"
            auth_host="${auth_domain}"
            auth_secure="true"
            z_public_url="https://${auth_domain}"

            echo "map \$http_x_forwarded_proto \$pref_proto { default \$scheme; }" > nginx/headers.map
            
            echo "SSL Certificate Selection:"
            echo "1) Generate a Self-Signed Certificate (Quick start)"
            echo "2) Provide paths to existing .crt and .key files"
            read -p "Select option (1-2): " cert_mode

            if [ "$cert_mode" = "1" ]; then
                if command -v openssl >/dev/null 2>&1; then
                    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                        -keyout certs/datastrat.key -out certs/datastrat.crt \
                        -subj "/C=US/ST=State/L=City/O=DataStrat/OU=IT/CN=${app_domain}"
                    sed -i.bak "s|^SSL_CERT_PATH=.*|SSL_CERT_PATH=./certs/datastrat.crt|g" .env
                    sed -i.bak "s|^SSL_KEY_PATH=.*|SSL_KEY_PATH=./certs/datastrat.key|g" .env
                    echo "Self-signed certificates generated in ./certs/"
                else
                    echo "Error: openssl not found. Please install it or provide paths to existing certs."
                    exit 1
                fi
            else
                read -p "Enter absolute path to your .crt file: " cert_path
                read -p "Enter absolute path to your .key file: " key_path
                sed -i.bak "s|^SSL_CERT_PATH=.*|SSL_CERT_PATH=${cert_path}|g" .env
                sed -i.bak "s|^SSL_KEY_PATH=.*|SSL_KEY_PATH=${key_path}|g" .env
            fi

            # Populate the SSL server block from template
            if [ -f "nginx/ssl.conf.template" ]; then
                cp nginx/ssl.conf.template nginx/ssl.conf
                # Replace variables in the template
                sed -i.bak "s|\${APP_DOMAIN}|${app_domain}|g" nginx/ssl.conf
                sed -i.bak "s|\${AUTH_DOMAIN}|${auth_domain}|g" nginx/ssl.conf
            else
                echo "Warning: nginx/ssl.conf.template not found. Skipping Port 443 setup."
            fi
            echo "Configured for Local SSL (Port 443 enabled)."
            ;;
        *)
            # Mode: No SSL
            app_url="http://${app_domain}"
            api_url="http://${app_domain}"
            auth_port="80"
            auth_host="${auth_domain}"
            auth_secure="false"
            z_public_url="http://${auth_domain}"
            echo "" > nginx/headers.map
            echo "" > nginx/ssl.conf
            echo "Configured for Plain HTTP (Port 80)."
            ;;
    esac
fi

sed -i.bak "s|^APP_URL=.*|APP_URL=${app_url}|g" .env
sed -i.bak "s|^NEXT_PUBLIC_API_URL=.*|NEXT_PUBLIC_API_URL=${api_url}|g" .env
sed -i.bak "s|^OIDC_CALLBACK_URL=.*|OIDC_CALLBACK_URL=${app_url}/api/v1/auth/oidc/callback|g" .env
sed -i.bak "s|^ZITADEL_PUBLIC_URL=.*|ZITADEL_PUBLIC_URL=${z_public_url}|g" .env
sed -i.bak "s|^ZITADEL_HOST=.*|ZITADEL_HOST=${auth_host}|g" .env

# Update Internal Routing Config
sed -i.bak "s|^AUTH_DOMAIN=.*|AUTH_DOMAIN=${auth_domain}|g" .env
sed -i.bak "s|^AUTH_PORT=.*|AUTH_PORT=${auth_port}|g" .env
sed -i.bak "s|^AUTH_HOST=.*|AUTH_HOST=${auth_host}|g" .env
sed -i.bak "s|^AUTH_SECURE=.*|AUTH_SECURE=${auth_secure}|g" .env

# --- LLM Settings ---
echo ""
echo "--- LLM (Language Model) Setup ---"
echo "Select your preferred LLM provider:"
echo "1) OpenAI (default)"
echo "2) Anthropic"
echo "3) Azure OpenAI"
echo "4) OpenRouter (Recommended for Claude 3.5 on API)"
read -p "Selection (1-4): " llm_choice

llm_provider="openai"
case $llm_choice in
    2) llm_provider="anthropic" ;;
    3) llm_provider="azure" ;;
    4) llm_provider="openrouter" ;;
    *) llm_provider="openai" ;;
esac

read -p "Enter your API Key: " llm_key
read -p "Enter the model name (e.g. gpt-4, claude-3-5-sonnet-20240620, anthropic/claude-3.5-sonnet): " llm_model

sed -i.bak "s|^LLM_PROVIDER=.*|LLM_PROVIDER=${llm_provider}|g" .env
sed -i.bak "s|^LLM_API_KEY=.*|LLM_API_KEY=${llm_key}|g" .env
sed -i.bak "s|^LLM_MODEL=.*|LLM_MODEL=${llm_model}|g" .env

if [ "$llm_provider" = "openrouter" ]; then
    sed -i.bak "s|^LLM_BASE_URL=.*|LLM_BASE_URL=https://openrouter.ai/api/v1|g" .env
fi

if [ "$llm_provider" = "azure" ]; then
    read -p "Enter your Azure OpenAI Endpoint (https://your-resource.openai.azure.com/): " azure_endpoint
    sed -i.bak "s|^AZURE_OPENAI_ENDPOINT=.*|AZURE_OPENAI_ENDPOINT=${azure_endpoint}|g" .env
fi

# --- Zitadel Settings ---
echo ""
echo "--- Identity & Access Setup (Zitadel) ---"
read -p "Generate a secure random Master Key for Zitadel? (Y/n): " gen_zitadel
if [[ ! $gen_zitadel =~ ^[Nn]$ ]]; then
    z_key=$(openssl rand -base64 32 | tr -d '\n' | cut -c1-32)
    sed -i.bak "s|^ZITADEL_MASTERKEY=.*|ZITADEL_MASTERKEY=${z_key}|g" .env
    echo "Generated Master Key successfully."
fi

# --- Security Secrets Generation ---
echo ""
echo "--- Security Secrets Generation ---"

# JWT Secret Key
read -p "Generate a secure random JWT Secret Key? (Y/n): " gen_jwt
if [[ ! $gen_jwt =~ ^[Nn]$ ]]; then
    jwt_key=$(openssl rand -base64 48 | tr -d '\n' | cut -c1-64)
    sed -i.bak "s|^JWT_SECRET_KEY=.*|JWT_SECRET_KEY=${jwt_key}|g" .env
    echo "Generated JWT Secret Key successfully."
fi

# Zitadel DB Password
read -p "Generate a secure random Zitadel DB password? (Y/n): " gen_zdb
if [[ ! $gen_zdb =~ ^[Nn]$ ]]; then
    zdb_pass=$(openssl rand -base64 24 | tr -d '\n' | cut -c1-32)
    sed -i.bak "s|^ZITADEL_DB_PASSWORD=.*|ZITADEL_DB_PASSWORD=${zdb_pass}|g" .env
    echo "Generated Zitadel DB password successfully."
fi

# MinIO / S3 credentials (only when using built-in local storage)
if [[ ! $use_local_storage =~ ^[Nn]$ ]]; then
    read -p "Generate secure MinIO storage credentials? (Y/n): " gen_minio
    if [[ ! $gen_minio =~ ^[Nn]$ ]]; then
        minio_access=$(openssl rand -hex 10)
        minio_secret=$(openssl rand -base64 32 | tr -d '\n' | cut -c1-40)
        sed -i.bak "s|^STORAGE_ACCESS_KEY=.*|STORAGE_ACCESS_KEY=${minio_access}|g" .env
        sed -i.bak "s|^STORAGE_SECRET_KEY=.*|STORAGE_SECRET_KEY=${minio_secret}|g" .env
        echo "Generated MinIO credentials successfully."
    fi
fi

# Cleanup sed backups
rm -f .env.bak

# Lock down file permissions so only the owner can read/write it
chmod 600 .env

echo ""
echo "==========================================================="
echo "  Setup Complete! Your .env file is ready and secured.    "
echo "==========================================================="
echo ""
echo "To start the application locally (DEVELOPMENT MODE with hot-reload):"
echo "  docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d"
echo ""
echo "To start the application for PRODUCTION (using docker-compose.prod.yml):"
echo "  docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d"
echo ""
