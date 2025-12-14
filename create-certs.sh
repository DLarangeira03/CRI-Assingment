#!/bin/bash
# Script to generate a self-signed CA, Service Certs, and CRL (Revocation List)

# --- Configuration ---
API_DOMAIN="api.cryptoassignment.corp"
FRONTEND_DOMAIN="www.cryptoassignment.corp"
IDP_DOMAIN="idp.cryptoassignment.corp"
POSTGRES_KC_CN="keycloak-db"
POSTGRES_APP_CN="app-db"
# ---------------------

echo "--- Setting up PKI Directory Structure ---"
mkdir -p certs/internal
cd certs/internal

# Clean start to ensure database consistency
rm -f *.pem *.srl *.cnf index.txt* serial* *.crt *.key *.p12 *.csr

# 1. Initialize OpenSSL Database (Required for Revocation)
touch index.txt
echo '1000' > serial
echo '1000' > crlnumber

# 2. Create a minimal OpenSSL Config for the CA
cat > openssl.cnf <<EOF
[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = .
certs             = .
crl_dir           = .
new_certs_dir     = .
database          = ./index.txt
serial            = ./serial
RANDFILE          = ./.rand
private_key       = ./ca.key
certificate       = ./ca.crt
crlnumber         = ./crlnumber
crl               = ./crl.pem
crl_extensions    = crl_ext
default_crl_days  = 30
default_days      = 365
default_md        = sha384
preserve          = no
policy            = policy_loose
copy_extensions   = copy

[ policy_loose ]
countryName             = optional
stateOrProvinceName     = optional
localityName            = optional
organizationName        = optional
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ crl_ext ]
authorityKeyIdentifier=keyid:always

[ req ]
default_bits        = 384
distinguished_name  = req_distinguished_name
string_mask         = utf8only
default_md          = sha384
x509_extensions     = v3_ca

[ req_distinguished_name ]
countryName                     = Country Name (2 letter code)
stateOrProvinceName             = State or Province Name
localityName                    = Locality Name
0.organizationName              = Organization Name
organizationalUnitName          = Organizational Unit Name
commonName                      = Common Name
emailAddress                    = Email Address

[ v3_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign

[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = placeholder
EOF

# 3. Generate Root CA
echo "--- Generating Root CA (ECDSA P-384) ---"
openssl ecparam -name secp384r1 -genkey -out ca.key
openssl req -config openssl.cnf -key ca.key -new -x509 -days 3650 -sha384 -extensions v3_ca \
    -out ca.crt -subj "/C=PT/ST=Coimbra/O=Crypto Corp/CN=Internal Root CA"

# Function to generate certs using the CA DB
gen_cert() {
    local name=$1
    local cn=$2
    local sans=$3
    
    echo "--- Generating Certificate: $name ($cn) ---"
    openssl ecparam -name secp384r1 -genkey -out ${name}.key
    
    # Update Config for SANs (Sed replaces 'placeholder' with actual DNS)
    sed -i "s/DNS\.1 = .*/$sans/" openssl.cnf
    
    openssl req -config openssl.cnf -new -key ${name}.key -out ${name}.csr \
        -subj "/C=PT/ST=Coimbra/O=Crypto Corp/CN=$cn"
    
    # Sign with CA and update DB
    openssl ca -config openssl.cnf -batch -notext -in ${name}.csr -out ${name}.crt -extensions v3_req -days 365
}

# 4. Generate Service Certificates
# Keycloak (IDP)
gen_cert "keycloak" "keycloak" "DNS.1 = keycloak-app\nDNS.2 = idp.cryptoassignment.corp"

# Backend (FIXED: Added fastapi_app)
gen_cert "fastapi" "fastapi_app" "DNS.1 = fastapi_app\nDNS.2 = $API_DOMAIN"

# Frontend (FIXED: Added frontend_app)
gen_cert "frontend_app" "frontend_app" "DNS.1 = frontend_app\nDNS.2 = $FRONTEND_DOMAIN"

# NGINX PQC Proxy
gen_cert "nginx_pqc" "nginx_pqc" "DNS.1 = nginx_pqc"

# Databases (Keycloak & App)
gen_cert "keycloak_db" "$POSTGRES_KC_CN" "DNS.1 = $POSTGRES_KC_CN"
gen_cert "app_db" "$POSTGRES_APP_CN" "DNS.1 = $POSTGRES_APP_CN"

# Public Proxy Certs (Matching docker-compose filenames)
gen_cert "$API_DOMAIN" "$API_DOMAIN" "DNS.1 = $API_DOMAIN"
gen_cert "$FRONTEND_DOMAIN" "$FRONTEND_DOMAIN" "DNS.1 = $FRONTEND_DOMAIN"
gen_cert "$IDP_DOMAIN" "$IDP_DOMAIN" "DNS.1 = $IDP_DOMAIN"

# 5. Format Conversions
echo "--- Converting formats for Keycloak/Java ---"
if [ -f "keycloak.crt" ]; then
    openssl pkcs12 -export -in keycloak.crt -inkey keycloak.key -out keycloak.p12 -name keycloak -passout pass:changeit
    openssl pkcs8 -topk8 -inform PEM -outform DER -in keycloak.key -out keycloak.pk8 -nocrypt
else
    echo "ERROR: keycloak.crt was not generated. Check previous errors."
    exit 1
fi

# 6. REVOCATION & CRL GENERATION
echo "--- Generating Dummy Cert for Revocation ---"
gen_cert "revoked_client" "Bad Actor" "DNS.1 = bad.actor"

if [ -f "revoked_client.crt" ]; then
    echo "--- Revoking 'Bad Actor' Certificate ---"
    # This updates index.txt marking the cert as 'R' (Revoked)
    openssl ca -config openssl.cnf -revoke revoked_client.crt -crl_reason keyCompromise
else
    echo "ERROR: revoked_client.crt not found. Skipping revocation."
fi

echo "--- Generating Certificate Revocation List (CRL) ---"
# Generates the crl.pem based on index.txt
openssl ca -config openssl.cnf -gencrl -out crl.pem

echo "CRL Generated at: certs/internal/crl.pem"

# Cleanup

#rm -f *.csr *.cnf *.srl index.txt* serial* crlnumber* revoked_client*
echo "--- Setup Complete ---"