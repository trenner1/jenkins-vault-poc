#!/usr/bin/env bash
# Auto-unseal script for Vault
# This script automatically unseals Vault using the stored keys

set -euo pipefail

VAULT_KEYS_FILE="${VAULT_KEYS_FILE:-./vault-keys.txt}"
VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"

echo "🔓 Auto-unsealing Vault..."

# Extract unseal keys from the keys file
UNSEAL_KEY_1=$(grep "Unseal Key 1:" "$VAULT_KEYS_FILE" | cut -d' ' -f4)
UNSEAL_KEY_2=$(grep "Unseal Key 2:" "$VAULT_KEYS_FILE" | cut -d' ' -f4)
UNSEAL_KEY_3=$(grep "Unseal Key 3:" "$VAULT_KEYS_FILE" | cut -d' ' -f4)

echo "Using unseal keys from: $VAULT_KEYS_FILE"

# Wait for Vault to be ready
echo "Waiting for Vault to be ready..."
until curl -s "$VAULT_ADDR/v1/sys/health" >/dev/null 2>&1; do
    echo "  Waiting for Vault..."
    sleep 2
done

# Check if already unsealed
if docker exec vault vault status 2>/dev/null | grep -q "Sealed.*false"; then
    echo "✅ Vault is already unsealed!"
    exit 0
fi

# Unseal with first 3 keys
echo "🔑 Unsealing with key 1/3..."
docker exec vault vault operator unseal "$UNSEAL_KEY_1" >/dev/null

echo "🔑 Unsealing with key 2/3..."
docker exec vault vault operator unseal "$UNSEAL_KEY_2" >/dev/null

echo "🔑 Unsealing with key 3/3..."
docker exec vault vault operator unseal "$UNSEAL_KEY_3" >/dev/null

# Verify unsealed
if docker exec vault vault status 2>/dev/null | grep -q "Sealed.*false"; then
    echo "✅ Vault successfully unsealed!"
else
    echo "❌ Failed to unseal Vault"
    exit 1
fi