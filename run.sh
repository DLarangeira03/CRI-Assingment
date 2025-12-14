#!/bin/bash

# --- Environment Configuration ---
HOSTS_FILE="/etc/hosts"
HOST_IP="127.0.0.1"

# Define all domains that must resolve to localhost (the Nginx proxy)
REQUIRED_DOMAINS=(
    "api.cryptoassignment.corp"
    "www.cryptoassignment.corp"
    "idp.cryptoassignment.corp"
)

echo "Starting Docker Compose Environment Setup..."
echo "------------------------------------------"

# --- 0. CHECKS AND SETUP ---

# A. Keycloak Database Volume Check
DB_VOLUME_DIR="./keycloak-db-data"
echo "0A. Checking and setting up Keycloak database volume directory: ${DB_VOLUME_DIR}"

if [ ! -d "${DB_VOLUME_DIR}" ]; then
    echo "    -> Directory '${DB_VOLUME_DIR}' not found. Creating it."
    mkdir -p "${DB_VOLUME_DIR}"
    # Keycloak DB container runs as user 999 (postgres), so we set the ownership
    echo "    -> Setting ownership to 999:999 for volume persistence (requires SUDO)."
    sudo chown 999:999 "${DB_VOLUME_DIR}"
    if [ $? -ne 0 ]; then
        echo "WARNING: Failed to set ownership on ${DB_VOLUME_DIR}. Keycloak-db might fail to start."
    fi
else
    echo "    -> Directory '${DB_VOLUME_DIR}' already exists. Skipping creation."
fi

# B. App Database Volume Check (NEW - Required for Part 2)
APP_DB_VOLUME_DIR="./app-db-data"
echo "0B. Checking and setting up App database volume directory: ${APP_DB_VOLUME_DIR}"

if [ ! -d "${APP_DB_VOLUME_DIR}" ]; then
    echo "    -> Directory '${APP_DB_VOLUME_DIR}' not found. Creating it."
    mkdir -p "${APP_DB_VOLUME_DIR}"
    # App DB also runs as user 999 (postgres)
    echo "    -> Setting ownership to 999:999 for volume persistence (requires SUDO)."
    sudo chown 999:999 "${APP_DB_VOLUME_DIR}"
    if [ $? -ne 0 ]; then
        echo "WARNING: Failed to set ownership on ${APP_DB_VOLUME_DIR}. App-db might fail to start."
    fi
else
    echo "    -> Directory '${APP_DB_VOLUME_DIR}' already exists. Skipping creation."
fi

# C. Certificates Check
CERTS_DIR="./certs"
SETUP_SCRIPT="./create-certs.sh"
CERTS_EXIST=false
if [ -d "${CERTS_DIR}" ] && [ "$(ls -A ${CERTS_DIR}/internal 2>/dev/null)" ]; then
    CERTS_EXIST=true
fi

if ! ${CERTS_EXIST}; then
    echo "0C. CRITICAL: Certificates folder is empty or missing. Executing ${SETUP_SCRIPT}."
    if [ -f "${SETUP_SCRIPT}" ]; then
        bash "${SETUP_SCRIPT}"
    else
        echo "ERROR: ${SETUP_SCRIPT} not found. Exiting."
        exit 1
    fi
elif [[ "$1" != "" ]]; then
    read -r -p "0C. Argument passed ($1). Do you want to re-execute setup.sh to generate NEW certificates? (y/N): " response
    case "$response" in
        [yY][eE][sS]|[yY])
            echo "    -> Re-executing ${SETUP_SCRIPT} to refresh certificates."
            bash "${SETUP_SCRIPT}"
            ;;
        *)
            echo "    -> Keeping existing certificates."
            ;;
    esac
fi

# 1. STOP AND REMOVE previous containers/networks/volumes
echo "1. Stopping and removing previous containers and dangling data..."
docker compose down --remove-orphans

# 2. BUILD AND RUN the updated services
echo "2. Building services and starting all services in detached mode..."
docker compose up --build -d

# Check if docker compose was successful before proceeding
if [ $? -ne 0 ]; then
    echo "ERROR: Docker Compose failed to build or start services. Please check the logs."
    exit 1
fi

# 3. CONFIGURE LOCAL HOSTS FILE
echo "3. Checking local machine's ${HOSTS_FILE} for required domain entries..."
echo "    -> This step requires SUDO access to map the domains to localhost (127.0.0.1)."

for DOMAIN in "${REQUIRED_DOMAINS[@]}"; do
    HOST_ENTRY="${HOST_IP} ${DOMAIN}"
    if grep -q "${HOST_ENTRY}" "${HOSTS_FILE}"; then
        echo "    -> Entry '${DOMAIN}' already exists. Skipping."
    else
        echo "    -> Entry '${DOMAIN}' not found. Adding..."
        # Use tee to append the entry to the hosts file using sudo
        echo "${HOST_ENTRY}" | sudo tee -a "${HOSTS_FILE}" > /dev/null
        if [ $? -eq 0 ]; then
            echo "    -> Successfully added: ${HOST_ENTRY}"
        else
            echo "WARNING: Could not update the hosts file for ${DOMAIN}. You may need to update it manually."
        fi
    fi
done


# 4. VERIFICATION
echo "------------------------------------------"
echo "Setup Complete!"
echo "Verification Steps:"
echo "1. Verify services are running: docker compose ps"
echo "2. Test all domain resolutions (should return 127.0.0.1):"
for DOMAIN in "${REQUIRED_DOMAINS[@]}"; do
    echo "    Testing ${DOMAIN}:"
    ping -c 1 "${DOMAIN}"
done

echo ""
echo "You should now be able to access the application via the PQC Nginx proxy at:"
echo "https://www.cryptoassignment.corp"
echo "https://api.cryptoassignment.corp"
echo "https://idp.cryptoassignment.corp (Keycloak Admin: admin/admin)"