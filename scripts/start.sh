#!/usr/bin/env bash
# Startup script for Jenkins-Vault POC
# Starts containers and automatically unseals Vault

set -euo pipefail

# Determine script and repo locations
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Search and source a .env from common locations and export variables
ENV_PATHS=("${PWD}/.env" "${SCRIPT_DIR}/.env" "${REPO_ROOT}/.env")
FOUND_ENV=""
for p in "${ENV_PATHS[@]}"; do
    if [[ -f "$p" ]]; then
        FOUND_ENV="$p"
        break
    fi
done

if [[ -n "$FOUND_ENV" ]]; then
    echo "Loading environment variables from $FOUND_ENV"
    set -a
    # shellcheck disable=SC1090
    source "$FOUND_ENV"
    set +a
else
    echo "WARNING: No .env file found in expected locations. Please ensure environment variables are set."
fi

# Normalize VAULT_ADDR for host execution
if [[ -z "${VAULT_ADDR:-}" ]]; then
    echo "Setting default VAULT_ADDR=http://localhost:8200"
    export VAULT_ADDR="http://localhost:8200"
else
    if [[ "$VAULT_ADDR" == *"vault:8200"* ]]; then
        echo "Converting Docker service address to localhost"
        export VAULT_ADDR="http://localhost:8200"
    fi
fi

# Ensure a Vault token is available
if [[ -z "${VAULT_TOKEN:-}" ]]; then
    if [[ -n "${VAULT_ROOT_TOKEN:-}" ]]; then
        echo "Using VAULT_ROOT_TOKEN as VAULT_TOKEN"
        export VAULT_TOKEN="$VAULT_ROOT_TOKEN"
    else
        echo "Error: Neither VAULT_TOKEN nor VAULT_ROOT_TOKEN environment variable is set"
        exit 1
    fi
fi

echo "Starting Jenkins-Vault POC..."

# Ensure vault configuration exists
VAULT_CONFIG_DIR="$REPO_ROOT/data/vault/config"
VAULT_CONFIG_FILE="$VAULT_CONFIG_DIR/vault.hcl"

if [[ ! -f "$VAULT_CONFIG_FILE" ]]; then
    echo "Creating Vault configuration at $VAULT_CONFIG_FILE..."
    mkdir -p "$VAULT_CONFIG_DIR"
    mkdir -p "$REPO_ROOT/data/vault/data"
    mkdir -p "$REPO_ROOT/data/vault/logs"
    
    cat > "$VAULT_CONFIG_FILE" <<EOF
ui = true
disable_mlock = true

storage "raft" {
  path = "/vault/data"
  node_id = "vault_node_1"
}

listener "tcp" {
  address = "0.0.0.0:8200"
  tls_disable = "true"
}

api_addr = "http://127.0.0.1:8200"
cluster_addr = "http://127.0.0.1:8201"
EOF
    echo "Vault configuration created successfully"
else
    echo "Vault configuration already exists at $VAULT_CONFIG_FILE"
fi

# Start containers from the repo root so docker compose finds the compose file
echo "Starting Docker containers..."
cd "$REPO_ROOT"
docker compose up -d

# Wait a bit for containers to be ready
echo "Waiting for containers to be ready..."
sleep 5

# Check if vault-keys.txt exists, if not, bootstrap Vault
VAULT_KEYS_FILE="$REPO_ROOT/vault-keys.txt"
if [[ ! -f "$VAULT_KEYS_FILE" ]]; then
    echo "vault-keys.txt not found - checking if Vault needs initialization..."
    
    # Wait a bit more for Vault to be fully ready for status checks
    sleep 3
    
    # Check if Vault is initialized
    VAULT_STATUS=$(docker exec vault vault status -format=json 2>/dev/null || true)
    if [[ -z "$VAULT_STATUS" ]]; then
        # If vault status failed, assume uninitialized
        INITIALIZED="false"
    else
        INITIALIZED=$(echo "$VAULT_STATUS" | jq -r '.initialized // false')
    fi
    
    if [[ "$INITIALIZED" == "false" ]]; then
        echo "Vault is not initialized - running bootstrap to generate keys..."
        BOOTSTRAP_SCRIPT="$REPO_ROOT/scripts/bootstrap-vault.sh"
        
        if [[ -f "$BOOTSTRAP_SCRIPT" ]]; then
            echo "Initializing Vault and generating keys..."
            VAULT_KEYS_FILE="$VAULT_KEYS_FILE" bash "$BOOTSTRAP_SCRIPT"
            echo "Bootstrap completed successfully!"
        else
            echo "ERROR: Bootstrap script not found at $BOOTSTRAP_SCRIPT"
            echo "Please run the following manually:"
            echo "  docker exec vault vault operator init -format=json > $VAULT_KEYS_FILE"
            exit 1
        fi
    else
        echo "ERROR: Vault is already initialized but vault-keys.txt is missing!"
        echo "This usually means the keys file was deleted or moved."
        echo "You need to restore the original vault-keys.txt file to proceed."
        echo "If you have lost the unseal keys, Vault data cannot be recovered."
        exit 1
    fi
fi

# Auto-unseal Vault (only if Vault is sealed)
echo "Checking Vault sealed status..."
# Query Vault status inside the container. If the container isn't ready this will be empty/return non-zero.
SEALED="$(docker exec vault vault status 2>/dev/null | grep -E "Sealed" | awk '{print $2}' || true)"
if [[ "$SEALED" == "true" ]]; then
    echo "Vault is sealed — running unseal script..."
    export VAULT_KEYS_FILE="$VAULT_KEYS_FILE"
    "$SCRIPT_DIR/unseal-vault.sh"
else
    echo "Vault is not sealed (or status not available); skipping unseal."
fi

# Set Vault token from keys file (use repo-root path)
if [[ -f "$VAULT_KEYS_FILE" ]]; then
    ROOT_TOKEN=$(grep "Initial Root Token:" "$VAULT_KEYS_FILE" | awk '{print $4}')
    if [[ -n "$ROOT_TOKEN" ]]; then
        export VAULT_TOKEN="$ROOT_TOKEN"
        echo "Vault token set from vault-keys.txt"
    else
        echo "WARNING: Could not extract root token from $VAULT_KEYS_FILE"
    fi
else
    echo "ERROR: vault-keys.txt not found at $VAULT_KEYS_FILE after bootstrap/unseal"
    exit 1
fi

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