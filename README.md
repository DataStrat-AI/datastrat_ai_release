# DataStrat AI Enterprise Appliance

This repository contains the deployment orchestrator files for the DataStrat AI appliance.

## 🚀 How to Install

1. Go to the **Releases** tab on the right side of this page.
2. Download the `datastrat-enterprise-deployment.zip` from the latest release.
3. Unzip the file on your secure server.
4. Run `./deploy.sh` to initialize your environment.
5. Run `docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d` to start the appliance.
