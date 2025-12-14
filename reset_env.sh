#!/bin/bash

# Configuration
APP_DB_DIR="./app-db-data"
KEYCLOAK_DB_DIR="./keycloak-db-data"
CERTS_DIR="./certs"
BACKEND_LOCAL_CERTS="./backend/certs"
# Added pycache target
BACKEND_PYCACHE="./backend/__pycache__"

echo "--- Resetting Environment ---"

# 1. Stop and remove containers, networks, and volumes
echo "1. Tearing down Docker services..."
docker compose down -v --remove-orphans

if [ $? -eq 0 ]; then
    echo "   [SUCCESS] Docker services stopped and removed."
else
    echo "   [WARNING] Docker compose down reported an error. Proceeding anyway."
fi

# 2. Remove Data Directories (Requires SUDO because they are owned by root/postgres)
echo "2. Removing persistent data volumes (sudo required)..."

if [ -d "$APP_DB_DIR" ]; then
    echo "   Removing $APP_DB_DIR..."
    sudo rm -rf "$APP_DB_DIR"
fi

if [ -d "$KEYCLOAK_DB_DIR" ]; then
    echo "   Removing $KEYCLOAK_DB_DIR..."
    sudo rm -rf "$KEYCLOAK_DB_DIR"
fi

# 3. Remove Certificates (Global and Backend-specific)
echo "3. Removing certificates..."
if [ -d "$CERTS_DIR" ]; then
    echo "   Removing global $CERTS_DIR..."
    rm -rf "$CERTS_DIR"
fi

if [ -d "$BACKEND_LOCAL_CERTS" ]; then
    echo "   Removing local backend certs ($BACKEND_LOCAL_CERTS)..."
    rm -rf "$BACKEND_LOCAL_CERTS"
fi

# 4. Remove PyCache
echo "4. Cleaning up Python cache..."
if [ -d "$BACKEND_PYCACHE" ]; then
    echo "   Removing $BACKEND_PYCACHE..."
    rm -rf "$BACKEND_PYCACHE"
fi


echo "--- Environment Reset Complete ---"
echo "You can now run ./run.sh to start fresh."