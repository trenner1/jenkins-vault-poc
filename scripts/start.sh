#!/usr/bin/env bash
# Startup script for Jenkins-Vault POC
# Starts containers and automatically unseals Vault

set -euo pipefail

# Set Vault environment variables
export VAULT_ADDR="http://localhost:8200"

echo "Starting Jenkins-Vault POC..."

# Start containers
echo "Starting Docker containers..."
docker compose up -d

# Wait a bit for containers to be ready
echo "Waiting for containers to be ready..."
sleep 5

# Auto-unseal Vault
echo "Auto-unsealing Vault..."
./unseal-vault.sh

# Set Vault token from keys file
export VAULT_TOKEN=$(grep "Initial Root Token:" ../vault-keys.txt | cut -d' ' -f4)
echo "Vault token set from vault-keys.txt"

# Check status
echo ""
echo "Container Status:"
docker ps --filter "name=vault" --filter "name=jenkins" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "Vault Status:"
docker exec vault vault status 2>/dev/null | grep -E "(Sealed|HA Mode|Version)" || echo "Vault not ready"

echo ""
echo "Setup Complete!"
echo "   Jenkins: http://localhost:8080"
echo "   Vault UI: http://localhost:8200"
echo ""
echo "To set environment variables in your shell, run:"
echo "export VAULT_ADDR=$VAULT_ADDR"
echo "export VAULT_TOKEN=$VAULT_TOKEN"