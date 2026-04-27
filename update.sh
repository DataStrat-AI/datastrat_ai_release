#!/bin/bash
# =============================================================================
# DataStrat AI - Update Script
# =============================================================================

echo "==========================================================="
echo "        DataStrat AI - Automated Update Utility           "
echo "==========================================================="
echo ""
echo "Pulling latest Docker images..."

# Pull the latest versions of all services defined in production compose files
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
