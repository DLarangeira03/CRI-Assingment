-- Enable pgcrypto extension for this database
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Create Products table
CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    -- Price is plain text as requested
    price DECIMAL(10, 2) NOT NULL,
    -- Discount codes are secrets and must be encrypted
    encrypted_discount_code BYTEA,
    currency VARCHAR(3) DEFAULT 'EUR',
    description TEXT
);

-- Seed Data using PGP_SYM_ENCRYPT with HARDCODED Key
INSERT INTO products (name, price, encrypted_discount_code, currency, description) VALUES
('Quantum Laptop', 1999.00, pgp_sym_encrypt('QUANTUM_SUMMER_25', 'SUPER_SECRET_DB_KEY'), 'EUR', 'High performance quantum computing station'),
('PQC Safe USB Key', 59.99, pgp_sym_encrypt('SECURE_KEY_10', 'SUPER_SECRET_DB_KEY'), 'EUR', 'Hardware encrypted storage'),
('Lattice-Based Course', 299.50, pgp_sym_encrypt('STUDENT_DISCOUNT_50', 'SUPER_SECRET_DB_KEY'), 'EUR', 'Advanced cryptography training');