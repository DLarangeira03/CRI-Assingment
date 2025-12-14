#!/bin/bash
# keycloak-entrypoint.sh

# Base command arguments
ARGS=(
    start
    --db-url-host=keycloak-db
    --db-url-database=keycloak
    --db-username=keycloak
    --db-password=keycloak
    --https-key-store-file=/opt/keycloak/certs/keycloak.p12
    --https-key-store-password=changeit
    --hostname=idp.cryptoassignment.corp
    --import-realm
)


echo "Executing command: /opt/keycloak/bin/kc.sh ${ARGS[@]}"
exec /opt/keycloak/bin/kc.sh "${ARGS[@]}"