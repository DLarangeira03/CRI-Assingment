import logging
import requests
import asyncpg
import os
import ssl
import pycryptodome
from fastapi import FastAPI, Depends, HTTPException, status, Header
from jose import jwt, jwk
from jose.exceptions import JWTError, ExpiredSignatureError
from typing import Dict, List

# ---------------------------
# Logging Configuration
# ---------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)
logger = logging.getLogger("fastapi_app")

# ---------------------------
# FastAPI App
# ---------------------------
app = FastAPI(title="Cryptography Assignment API")

# ---------------------------
# Keycloak Configuration
# ---------------------------
KEYCLOAK_ISSUER = "https://idp.cryptoassignment.corp/realms/crypto-realm"
KEYCLOAK_JWKS_URL = f"{KEYCLOAK_ISSUER}/protocol/openid-connect/certs"
KEYCLOAK_AUDIENCE = "crypto-frontend"
CA_CERT_PATH = "/app/certs/ca.crt"

# ---------------------------
# Database Configuration
# ---------------------------
DB_DSN = "postgresql://app_user:app_password@app-db:5432/app_db"

# Secret Handling
DB_SECRET_KEY = os.getenv("APP_DB_SECRET")
if not DB_SECRET_KEY:
    logger.warning("⚠️ APP_DB_SECRET not found in environment! Using fallback default.")
    DB_SECRET_KEY = "SUPER_SECRET_DB_KEY"
else:
    logger.info("✅ APP_DB_SECRET loaded successfully from environment.")

# ---------------------------
# SSL Context Creation (FIXED)
# ---------------------------
def create_ssl_context():
    """
    Creates a proper SSLContext for asyncpg to connect to Postgres via mTLS.
    """
    # 1. Create a context that verifies the server (Postgres) certificate
    ssl_ctx = ssl.create_default_context(ssl.Purpose.SERVER_AUTH, cafile="/app/certs/ca.crt")
    
    # 2. Load the Client Certificate and Key (for mTLS authentication)
    ssl_ctx.load_cert_chain(
        certfile="/app/certs/fastapi.crt",
        keyfile="/app/certs/fastapi.key"
    )
    
    # 3. Security Settings
    ssl_ctx.check_hostname = False # We trust our internal DNS/CN mapping
    ssl_ctx.verify_mode = ssl.CERT_REQUIRED
    
    return ssl_ctx

# ---------------------------
# Helper: Get JWKS Keys
# ---------------------------
def get_jwks() -> Dict[str, dict]:
    try:
        response = requests.get(KEYCLOAK_JWKS_URL, timeout=5, verify=CA_CERT_PATH)
        response.raise_for_status()
        jwks = response.json()
        return {key["kid"]: key for key in jwks["keys"]}
    except Exception as e:
        logger.error(f"Failed to fetch JWKS: {e}")
        raise HTTPException(status_code=500, detail="Failed to fetch JWKS")

# ---------------------------
# Verify JWT Token
# ---------------------------
def verify_access_token(authorization: str = Header(None)) -> Dict:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing Authorization header")

    token = authorization.split(" ")[1]

    try:
        unverified_header = jwt.get_unverified_header(token)
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid JWT header")

    kid = unverified_header.get("kid")
    jwks = get_jwks()

    if kid not in jwks:
        raise HTTPException(status_code=401, detail="Unknown 'kid' in token")

    key_data = jwks[kid]
    try:
        public_key = jwk.construct(key_data)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to construct public key: {e}")

    try:
        payload = jwt.decode(
            token,
            public_key,
            algorithms=[key_data["alg"]],
            audience=KEYCLOAK_AUDIENCE,
            issuer=KEYCLOAK_ISSUER
        )
        return payload
    except ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired")
    except JWTError as e:
        raise HTTPException(status_code=401, detail=f"Invalid token: {e}")

# ---------------------------
# Endpoints
# ---------------------------
@app.get("/api/v1/public/status")
async def public_endpoint():
    return {"status": "ok", "service": "fastapi_app"}

@app.get("/protected/shop-data")
async def protected_shop_data(user: Dict = Depends(verify_access_token)):
    logger.info(f"Accessing Shop Data for user: {user.get('preferred_username')}")
    products = []
    
    try:
        # FIXED: Pass the SSLContext object, not a dict
        conn = await asyncpg.connect(
            DB_DSN,
            ssl=create_ssl_context()
        )
        
        # Query: Select name, plain price, and DECRYPT the discount code using the Env Var Key
        query = """
            SELECT 
                name, 
                price,
                pgp_sym_decrypt(encrypted_discount_code, $1) as discount_code, 
                currency, 
                description 
            FROM products
        """
        
        rows = await conn.fetch(query, DB_SECRET_KEY)
        await conn.close()
        
        for row in rows:
            products.append({
                "item": row['name'],
                "price": float(row['price']),
                "secret_code": row['discount_code'], # Decrypted value
                "currency": row['currency'],
                "description": row['description']
            })
            
    except Exception as e:
        logger.error(f"Database error: {e}")
        raise HTTPException(status_code=500, detail="Internal Database Error")

    return {
        "user": user.get("preferred_username"),
        "email": user.get("email"),
        "data": products
    }

@app.get("/")
async def root_endpoint():
    return {"status": "ok", "service": "fastapi_app"}
