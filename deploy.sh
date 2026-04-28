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
    
    read -p "PostgreSQL DATABASE_URL (e.g. postgresql://user:pass@rds.amazonaws.com:5432/db): " db_url
    read -p "Redis URL (e.g. redis://elasticache.amazonaws.com:6379/0): " redis_url
    read -p "Qdrant URL (e.g. https://your-cluster.aws.cloud.qdrant.io:6333): " qdrant_url
    
    echo ""
    echo "[S3-Compatible Object Storage]"
    read -p "S3 Endpoint URL (e.g. https://s3.amazonaws.com or https://storage.googleapis.com): " s3_url
    read -p "S3 Access Key: " s3_access
    read -p "S3 Secret Key: " s3_secret
    read -p "S3 Bucket Name: " s3_bucket

    # Replace values in .env
    sed -i.bak "s|^DATABASE_URL=.*|DATABASE_URL=${db_url}|g" .env
    sed -i.bak "s|^REDIS_URL=.*|REDIS_URL=${redis_url}|g" .env
    sed -i.bak "s|^QDRANT_URL=.*|QDRANT_URL=${qdrant_url}|g" .env
    sed -i.bak "s|^STORAGE_ENDPOINT_URL=.*|STORAGE_ENDPOINT_URL=${s3_url}|g" .env
    sed -i.bak "s|^STORAGE_ACCESS_KEY=.*|STORAGE_ACCESS_KEY=${s3_access}|g" .env
    sed -i.bak "s|^STORAGE_SECRET_KEY=.*|STORAGE_SECRET_KEY=${s3_secret}|g" .env
    sed -i.bak "s|^STORAGE_BUCKET_NAME=.*|STORAGE_BUCKET_NAME=${s3_bucket}|g" .env
    
    # We leave COMPOSE_PROFILES empty so local storage containers don't start
    echo "COMPOSE_PROFILES=" >> .env
else
    # User is using local storage
    echo "Using default local storage containers."
    echo "COMPOSE_PROFILES=local-storage" >> .env
fi

# --- Domain & Routing Setup ---
echo ""
echo "--- Domain & Routing Setup ---"
read -p "Enter your main application domain (e.g., app.datastrat.ai or localhost): " app_domain
read -p "Enter your authentication domain for Zitadel (e.g., auth.datastrat.ai or localhost): " auth_domain

# Default to localhost if empty
app_domain=${app_domain:-localhost}
auth_domain=${auth_domain:-localhost}

if [ "$app_domain" = "localhost" ]; then
    app_url="http://localhost:3000"
    api_url="http://localhost:8000"
    auth_port="8080"
    auth_host="localhost:8080"
    auth_secure="false"
    z_public_url="http://localhost:8080"
else
    # In production with a domain, Nginx routes over port 80
    app_url="http://${app_domain}"
    api_url="http://${app_domain}"
    auth_port="80"
    auth_host="${auth_domain}"
    auth_secure="false" # Change to true if using SSL/HTTPS
    z_public_url="http://${auth_domain}"
fi

sed -i.bak "s|^APP_URL=.*|APP_URL=${app_url}|g" .env
sed -i.bak "s|^NEXT_PUBLIC_API_URL=.*|NEXT_PUBLIC_API_URL=${api_url}|g" .env
sed -i.bak "s|^OIDC_CALLBACK_URL=.*|OIDC_CALLBACK_URL=${app_url}/api/v1/auth/oidc/callback|g" .env
sed -i.bak "s|^ZITADEL_PUBLIC_URL=.*|ZITADEL_PUBLIC_URL=${z_public_url}|g" .env

# Append the new AUTH_ vars so docker-compose can pick them up for Zitadel
echo "" >> .env
echo "# Routing Config" >> .env
echo "AUTH_DOMAIN=${auth_domain}" >> .env
echo "AUTH_PORT=${auth_port}" >> .env
echo "AUTH_HOST=${auth_host}" >> .env
echo "AUTH_SECURE=${auth_secure}" >> .env

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

# Cleanup sed backups
rm -f .env.bak

# Lock down file permissions so only the owner can read/write it
chmod 600 .env

echo ""
echo "==========================================================="
echo "Setup Complete! Your .env file is ready and secured."
echo "==========================================================="
echo ""
echo "To start the application locally (development mode):"
echo "  docker compose up -d"
echo ""
echo "To start the application for PRODUCTION (using docker-compose.prod.yml):"
echo "  docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d"
echo ""
