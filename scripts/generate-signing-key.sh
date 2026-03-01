#!/usr/bin/env bash
# Generate an Ed25519 key pair for the Canopy package registry.
#
# Run this on an air-gapped machine. Store the private key securely.
# The public key should be embedded in Crypto/TrustedKeys.hs.
#
# Usage:
#   bash scripts/generate-signing-key.sh
#
# Requirements:
#   - OpenSSL with Ed25519 support (1.1.1+)
#   - xxd (usually from vim or vim-common)

set -euo pipefail

PRIVATE_KEY_FILE="canopy-registry.key"
PUBLIC_KEY_FILE="canopy-registry.pub"

if [ -f "$PRIVATE_KEY_FILE" ]; then
  echo "ERROR: $PRIVATE_KEY_FILE already exists. Remove it first or choose a different name."
  exit 1
fi

echo "Generating Ed25519 key pair..."

openssl genpkey -algorithm ed25519 -outform DER -out "$PRIVATE_KEY_FILE"
openssl pkey -in "$PRIVATE_KEY_FILE" -inform DER -pubout -outform DER -out "$PUBLIC_KEY_FILE"

# Extract raw 32-byte public key (skip DER header) and convert to hex
PUBLIC_KEY_HEX=$(tail -c 32 "$PUBLIC_KEY_FILE" | xxd -p -c 32)
KEY_ID="${PUBLIC_KEY_HEX:0:16}"

echo ""
echo "Public key (hex):  $PUBLIC_KEY_HEX"
echo "Key ID (16 chars): $KEY_ID"
echo ""
echo "Add this to Crypto/TrustedKeys.hs in the registryKeyHexValues list:"
echo ""
echo "  registryKeyHexValues ="
echo "    [ \"$PUBLIC_KEY_HEX\""
echo "    ]"
echo ""
echo "Private key saved to: $PRIVATE_KEY_FILE"
echo "Public key saved to:  $PUBLIC_KEY_FILE"
echo ""
echo "IMPORTANT: Store $PRIVATE_KEY_FILE in a secure, air-gapped location."
echo "           Never commit it to version control."
