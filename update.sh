#!/bin/bash
# =============================================================================
# DataStrat AI - Automated Update & Release Sync Utility
# =============================================================================

set -e

echo "==========================================================="
echo "        DataStrat AI - Automated Update Utility           "
echo "==========================================================="
echo ""

TEMP_DIR="/tmp/datastrat-update-$$"
RELEASE_ZIP_URL="https://github.com/DataStrat-AI/datastrat_ai_release/releases/latest/download/datastrat-enterprise-deployment.zip"

# -----------------------------------------------------------------------------
# STAGE 1: Fetch Latest Release Archive from GitHub
# -----------------------------------------------------------------------------
if [ "$1" != "--skip-fetch" ]; then
    echo "[Stage 1/5] Fetching latest release package from GitHub Releases..."
    mkdir -p "$TEMP_DIR"

    FETCH_SUCCESS=false
    if command -v curl >/dev/null 2>&1; then
        if curl -sSL "$RELEASE_ZIP_URL" -o "$TEMP_DIR/release.zip"; then
            FETCH_SUCCESS=true
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget -q "$RELEASE_ZIP_URL" -O "$TEMP_DIR/release.zip"; then
            FETCH_SUCCESS=true
        fi
    fi

    if [ "$FETCH_SUCCESS" = true ] && [ -s "$TEMP_DIR/release.zip" ]; then
        echo "-> Latest release archive downloaded successfully."
        
        echo "[Stage 2/5] Unpacking and updating deployment configurations..."
        if command -v unzip >/dev/null 2>&1; then
            unzip -q -o "$TEMP_DIR/release.zip" -d "$TEMP_DIR/extracted"
        else
            echo "Warning: 'unzip' utility not found. Skipping file extraction."
        fi

        if [ -d "$TEMP_DIR/extracted" ]; then
            # Check if update.sh itself was updated and trigger self-re-execution
            SELF_HASH_BEFORE=""
            SELF_HASH_AFTER=""
            if command -v sha256sum >/dev/null 2>&1; then
                SELF_HASH_BEFORE=$(sha256sum "$0" | awk '{print $1}')
                SELF_HASH_AFTER=$(sha256sum "$TEMP_DIR/extracted/update.sh" 2>/dev/null | awk '{print $1}')
            elif command -v md5 >/dev/null 2>&1; then
                SELF_HASH_BEFORE=$(md5 -q "$0")
                SELF_HASH_AFTER=$(md5 -q "$TEMP_DIR/extracted/update.sh" 2>/dev/null)
            fi

            # Sync extracted files excluding runtime host state (.env, certs/)
            if command -v rsync >/dev/null 2>&1; then
                rsync -av --exclude='.env' --exclude='certs/' "$TEMP_DIR/extracted/" ./ >/dev/null 2>&1 || true
            else
                cp -r "$TEMP_DIR/extracted/"* ./ 2>/dev/null || true
            fi
            chmod +x deploy.sh update.sh 2>/dev/null || true

            # If update.sh itself was updated, re-execute the new script process
            if [ -n "$SELF_HASH_BEFORE" ] && [ -n "$SELF_HASH_AFTER" ] && [ "$SELF_HASH_BEFORE" != "$SELF_HASH_AFTER" ]; then
                echo "-> Update script was upgraded to the latest version. Re-executing pipeline..."
                rm -rf "$TEMP_DIR"
                exec "$0" --skip-fetch "$@"
            fi
        fi
    else
        echo "Notice: Could not fetch latest release archive. Proceeding with existing local configuration files."
    fi

    # Clean up temp folder
    rm -rf "$TEMP_DIR"
else
    echo "-> Skipping release download (re-executed from updated script)."
fi

# -----------------------------------------------------------------------------
# STAGE 2: Environment Configuration Auditor (.env Sync)
# -----------------------------------------------------------------------------
if [ -f ".env" ] && [ -f ".env.example" ]; then
    echo ""
    echo "[Stage 3/5] Auditing environment configuration (.env)..."
    
    MISSING_KEYS=()
    while IFS= read -r line || [ -n "$line" ]; do
        # Ignore comments and blank lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        
        var_name=$(echo "$line" | cut -d '=' -f 1 | xargs)
        [ -z "$var_name" ] && continue
        
        if ! grep -qE "^[[:space:]]*${var_name}[[:space:]]*=" .env; then
            MISSING_KEYS+=("$var_name")
        fi
    done < .env.example

    if [ ${#MISSING_KEYS[@]} -gt 0 ]; then
        echo ""
        echo "==========================================================="
        echo "        DataStrat AI - Configuration Auditor             "
        echo "==========================================================="
        echo "New features have been added to the application!"
        echo "We need a few quick details to configure them for your server."
        echo ""

        IS_INTERACTIVE=false
        if [ -t 0 ]; then
            IS_INTERACTIVE=true
        fi

        for var in "${MISSING_KEYS[@]}"; do
            default_val=$(grep -E "^[[:space:]]*${var}[[:space:]]*=" .env.example | cut -d '=' -f 2- | xargs)

            case "$var" in
                GRAFANA_ADMIN_USER)
                    echo "-----------------------------------------------------------"
                    echo "[ Monitoring Dashboard Setup ]"
                    if [ "$IS_INTERACTIVE" = true ]; then
                        read -p "Please enter the admin username for Grafana [admin]: " user_input
                        val=${user_input:-admin}
                    else
                        val="admin"
                    fi
                    ;;
                GRAFANA_ADMIN_PASSWORD)
                    echo "-----------------------------------------------------------"
                    echo "[ Monitoring Dashboard Security ]"
                    auto_pass=$(openssl rand -hex 12 2>/dev/null || date +%s | md5sum | head -c 16)
                    if [ "$IS_INTERACTIVE" = true ]; then
                        read -p "Please enter the admin password for Grafana (press Enter to generate a secure password): " user_input
                        val=${user_input:-$auto_pass}
                    else
                        val="$auto_pass"
                    fi
                    echo "-> Configured Grafana admin password."
                    ;;
                JWT_SECRET_KEY)
                    echo "-----------------------------------------------------------"
                    echo "[ Security - JWT Secret Key ]"
                    auto_secret=$(openssl rand -hex 24 2>/dev/null || date +%s | md5sum | head -c 32)
                    if [ "$IS_INTERACTIVE" = true ]; then
                        read -p "Please enter JWT Secret Key (press Enter to auto-generate): " user_input
                        val=${user_input:-$auto_secret}
                    else
                        val="$auto_secret"
                    fi
                    ;;
                *)
                    if [ "$IS_INTERACTIVE" = true ]; then
                        read -p "Setting '${var}' [${default_val}]: " user_input
                        val=${user_input:-$default_val}
                    else
                        val="$default_val"
                    fi
                    ;;
            esac

            echo "${var}=${val}" >> .env
            echo "-> Saved to .env: ${var}=${val}"
        done
        echo ""
        echo "Environment configuration successfully synchronized!"
        echo "==========================================================="
        echo ""
    fi
fi

# -----------------------------------------------------------------------------
# STAGE 3: Pull Latest Images & Recycle Stack
# -----------------------------------------------------------------------------
echo ""
echo "[Stage 4/5] Reclaiming disk space and pulling latest Docker container images..."
docker image prune -a -f
docker compose -f docker-compose.yml -f docker-compose.prod.yml pull || docker compose pull

echo ""
echo "[Stage 5/5] Recrafting and restarting container stack..."
docker compose -f docker-compose.yml -f docker-compose.prod.yml down || docker compose down
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d || docker compose up -d

echo ""
echo "==========================================================="
echo " Update Complete! Application is running the latest version."
echo "==========================================================="
echo ""
docker compose ps
