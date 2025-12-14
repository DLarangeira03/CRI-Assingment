#!/bin/bash
set -e

# Initialize AIDE if database doesn't exist
if [ ! -f /var/lib/aide/aide.db.gz ]; then
    echo "Initializing AIDE integrity database..."
    aide --init --config /etc/aide/aide.conf
    mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
    echo "AIDE initialization complete."
else
    echo "Running AIDE integrity check..."
    aide --check --config /etc/aide/aide.conf || echo "WARNING: AIDE found changes!"
fi

# Hand off to the original entrypoint
exec /usr/local/bin/docker-entrypoint.sh "$@"