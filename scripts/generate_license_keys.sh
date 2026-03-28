#!/usr/bin/env bash
# Generates an Ed25519 keypair for license token signing.
#
# Private key → store as LICENSE_SIGNING_PRIVATE_KEY env var on the server (Vercel)
# Public key  → embed in LicenseValidator.swift as a base64 constant
#
# Usage: ./scripts/generate_license_keys.sh

set -euo pipefail

out_dir="${1:-.}"

openssl genpkey -algorithm Ed25519 -out "${out_dir}/license_private.pem" 2>/dev/null
openssl pkey -in "${out_dir}/license_private.pem" -pubout -out "${out_dir}/license_public.pem" 2>/dev/null

# Extract raw 32-byte public key (skip PEM header/ASN.1 wrapper) and base64 encode
public_key_b64=$(openssl pkey -in "${out_dir}/license_private.pem" -pubout -outform DER 2>/dev/null | tail -c 32 | base64)

# Extract raw 32-byte private key seed for Node.js crypto
private_key_pem=$(cat "${out_dir}/license_private.pem")

echo ""
echo "=== License Signing Keys Generated ==="
echo ""
echo "--- Server env var (add to Vercel / .env.local) ---"
echo "LICENSE_SIGNING_PRIVATE_KEY=\"$(cat "${out_dir}/license_private.pem" | base64 | tr -d '\n')\""
echo ""
echo "--- Swift constant (embed in LicenseValidator.swift) ---"
echo "static let publicKeyBase64 = \"${public_key_b64}\""
echo ""
echo "PEM files written to: ${out_dir}/license_private.pem, ${out_dir}/license_public.pem"
echo "IMPORTANT: Do NOT commit license_private.pem to git!"
