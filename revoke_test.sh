#!/bin/bash

# Configuration
CERTS_DIR="certs/internal"
CA_CONFIG="openssl.cnf"
TARGET_CERT="fastapi.crt"
CRL_FILE="crl.pem"
NGINX_CONTAINER="nginx_pqc"
TEST_URL="https://api.cryptoassignment.corp/api/v1/public/status"

echo "--- Simulating Certificate Revocation for ${TARGET_CERT} ---"

# Check if certificates directory exists
if [ ! -d "${CERTS_DIR}" ]; then
    echo "Error: Certificates directory ${CERTS_DIR} not found."
    exit 1
fi

cd "${CERTS_DIR}"

# 1. Revoke the certificate
echo "1. Revoking certificate: ${TARGET_CERT}..."
if [ -f "${TARGET_CERT}" ]; then
    openssl ca -config "${CA_CONFIG}" -revoke "${TARGET_CERT}" -crl_reason keyCompromise -batch
    if [ $? -eq 0 ]; then
        echo "   [SUCCESS] Certificate revoked."
    else
        echo "   [ERROR] Failed to revoke certificate."
        exit 1
    fi
else
    echo "   [ERROR] Certificate file ${TARGET_CERT} not found."
    exit 1
fi

# 2. Update the CRL
echo "2. Generating new CRL..."
openssl ca -config "${CA_CONFIG}" -gencrl -out "${CRL_FILE}"
if [ $? -eq 0 ]; then
    echo "   [SUCCESS] CRL updated at ${CERTS_DIR}/${CRL_FILE}"
else
    echo "   [ERROR] Failed to generate CRL."
    exit 1
fi

# 3. Verify Revocation in CRL
echo "3. Verifying revocation in CRL..."
# Extract the serial number of the revoked cert to verify
SERIAL=$(openssl x509 -in "${TARGET_CERT}" -noout -serial | cut -d= -f2)
echo "   Target Serial Number: ${SERIAL}"

# Check if that serial number appears in the CRL revocation list
openssl crl -in "${CRL_FILE}" -text | grep -A 1 "Serial Number: ${SERIAL}" > /dev/null

if [ $? -eq 0 ]; then
    echo "   [SUCCESS] Revocation confirmed in CRL for Serial: ${SERIAL}"
else
    echo "   [ERROR] Revoked serial number not found in CRL."
    exit 1
fi

# 4. Reload NGINX
echo "4. Reloading NGINX to apply CRL changes..."
docker restart "${NGINX_CONTAINER}"

if [ $? -eq 0 ]; then
    echo "   [SUCCESS] NGINX restarted."
else
    echo "   [ERROR] Failed to restart NGINX."
    exit 1
fi

# Wait for NGINX to fully initialize
echo "   Waiting 10 seconds for NGINX to stabilize..."
sleep 10

# 5. Verify with Curl
echo "5. Verifying access denial with Curl..."
echo "   Target URL: ${TEST_URL}"
# We use -k because we are testing NGINX's trust of the backend, not our trust of NGINX.
# We expect HTTP 502 (Bad Gateway) because NGINX will reject the upstream connection due to the CRL.

HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" "${TEST_URL}")

echo "   Received HTTP Status: ${HTTP_CODE}"

if [ "$HTTP_CODE" == "502" ]; then
    echo "   [SUCCESS] Revocation Enforced! NGINX blocked the backend (502 Bad Gateway)."
elif [ "$HTTP_CODE" == "400" ]; then
    echo "   [SUCCESS] Revocation Enforced! NGINX blocked the request (400 Bad Request / SSL Error)."
elif [ "$HTTP_CODE" == "200" ]; then
    echo "   [FAILURE] Revocation FAILED! Backend is still accessible (200 OK)."
    exit 1
else
    echo "   [WARNING] Unexpected status code: ${HTTP_CODE}. (000 means connection refused/DNS error)"
fi

# 6. Print NGINX Logs
echo "--- NGINX Logs (Last 20 lines) ---"
docker logs --tail 20 "${NGINX_CONTAINER}"
echo "----------------------------------"

echo "--- Simulation Complete ---"