#!/bin/bash
# =============================================================================
# DataStrat AI - Automated Update Utility & Configuration Auditor
# =============================================================================

echo "==========================================================="
echo "        DataStrat AI - Automated Update Utility           "
echo "==========================================================="
echo ""

# -----------------------------------------------------------------------------
# Smart .env Audit & Auto-Migration Utility
# -----------------------------------------------------------------------------
if [ -f ".env" ] && [ -f ".env.example" ]; then
    echo "Auditing environment configuration (.env)..."
    
    MISSING_KEYS=()
    while IFS='=' read -r key val || [ -n "$key" ]; do
        # Ignore comments and empty lines
        [[ "$key" =~ ^#.*$ ]] && continue
        [[ -z "$key" ]] && continue
        
        # Clean variable name
        var_name=$(echo "$key" | xargs)
        
        if ! grep -q "^${var_name}=" .env && ! grep -q "^${var_name} =" .env; then
            MISSING_KEYS+=("$var_name")
        fi
    done < .env.example

    if [ ${#MISSING_KEYS[@]} -gt 0 ]; then
        echo ""
        echo "==========================================================="
        echo "   DataStrat AI - New Configuration Settings Detected      "
        echo "==========================================================="
        echo "New services or features were introduced in this update."
        echo "We will now configure the missing settings for your server."
        echo ""

        IS_INTERACTIVE=false
        if [ -t 0 ]; then
            IS_INTERACTIVE=true
        fi

        for var in "${MISSING_KEYS[@]}"; do
            default_val=$(grep "^${var}=" .env.example | cut -d '=' -f 2-)

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

echo "Pulling latest Docker images..."
docker compose -f docker-compose.yml -f docker-compose.prod.yml pull

echo ""
echo "Recreating and restarting containers with new images..."
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d

echo ""
echo "Cleaning up dangling and unused images to free up space..."
docker image prune -f

echo ""
echo "==========================================================="
echo "Update Complete! The application is running the latest version."
echo "==========================================================="
