#!/usr/bin/env bash
set -euo pipefail

## Load environment variables from a .env file (search multiple likely locations)
# Allow running this script from the repo root or from vault/scripts/
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_PATHS=("${PWD}/.env" "${SCRIPT_DIR}/.env" "${SCRIPT_DIR}/../.env" "${SCRIPT_DIR}/../../.env")
FOUND_ENV=""
for p in "${ENV_PATHS[@]}"; do
  if [[ -f "$p" ]]; then
    FOUND_ENV="$p"
    break
  fi
done

if [[ -n "$FOUND_ENV" ]]; then
  echo "Loading environment variables from $FOUND_ENV"
  # Source and export variables from the env file (ignore comments and empty lines)
  set -a
  # shellcheck disable=SC1090
  source "$FOUND_ENV"
  set +a
  # Explicitly export key variables for parent shell
  export VAULT_ADDR VAULT_TOKEN
else
  echo "WARNING: No .env file found in expected locations. Please ensure environment variables are set."
fi

# Check required environment variables
if [[ -z "$VAULT_ADDR" ]]; then
    echo "Setting default VAULT_ADDR=http://localhost:8200"
    export VAULT_ADDR="http://localhost:8200"
else
    # If VAULT_ADDR uses docker service name, convert to localhost for host execution
    if [[ "$VAULT_ADDR" == *"vault:8200"* ]]; then
        echo "Converting Docker service address to localhost"
        export VAULT_ADDR="http://localhost:8200"
    fi
fi

if [[ -z "$VAULT_TOKEN" ]]; then
    if [[ -n "$VAULT_ROOT_TOKEN" ]]; then
        echo "Using VAULT_ROOT_TOKEN as VAULT_TOKEN"
        export VAULT_TOKEN="$VAULT_ROOT_TOKEN"
    else
        echo "Error: Neither VAULT_TOKEN nor VAULT_ROOT_TOKEN environment variable is set"
        exit 1
    fi
fi

# Resolve repo root for locating vault-keys and bootstrap script
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BOOTSTRAP_SCRIPT="$REPO_ROOT/scripts/bootstrap-vault.sh"

JENKINS_URL="${JENKINS_URL:-http://localhost:8080}"
PUBKEY_PATH="${PUBKEY_PATH:-$REPO_ROOT/keys/jenkins-oidc.pub}"
POLICY_DIR="${POLICY_DIR:-$REPO_ROOT/vault/policies}"
VAULT_KEYS_FILE="${VAULT_KEYS_FILE:-$REPO_ROOT/vault-keys.txt}"

# If vault-keys.txt is missing, check whether Vault needs initialization. If so,
# run the bootstrap script which runs `vault operator init` inside the container
# and writes the keys to $VAULT_KEYS_FILE.
if [[ ! -f "$VAULT_KEYS_FILE" ]]; then
  echo "vault-keys.txt not found at $VAULT_KEYS_FILE"
  # Check Vault health for initialization status (use vault status)
  if vault status >/dev/null 2>&1; then
    INIT_OUT=$(vault status -format=json 2>/dev/null || true)
    if [[ -n "$INIT_OUT" ]]; then
      initialized=$(printf '%s' "$INIT_OUT" | jq -r '.initialized')
      sealed=$(printf '%s' "$INIT_OUT" | jq -r '.sealed')
      if [[ "$initialized" == "false" ]]; then
        echo "Vault is not initialized; running bootstrap to initialize and generate keys..."
        if [[ -f "$BOOTSTRAP_SCRIPT" ]]; then
          echo "Invoking bootstrap script: $BOOTSTRAP_SCRIPT"
          VAULT_KEYS_FILE="$VAULT_KEYS_FILE" bash "$BOOTSTRAP_SCRIPT"
        else
          echo "Bootstrap script not found: $BOOTSTRAP_SCRIPT"
          exit 1
        fi
      elif [[ "$initialized" == "true" ]]; then
        echo "ERROR: Vault is already initialized but vault-keys.txt is missing!"
        echo "This usually means the keys file was deleted or moved."
        echo "You need to restore the original vault-keys.txt file to proceed."
        echo "If you have lost the unseal keys, Vault data cannot be recovered."
        exit 1
      else
        echo "Vault status unclear (initialized=$initialized sealed=$sealed). Please check manually."
        exit 1
      fi
    else
      echo "Could not parse 'vault status' output. Ensure Vault CLI and VAULT_ADDR/VAULT_TOKEN are set."
      exit 1
    fi
  else
    echo "Error: 'vault status' failed — is Vault reachable at $VAULT_ADDR?"
    exit 1
  fi
fi

# Extract root token from vault-keys.txt (prioritize over .env file)
if [[ -f "$VAULT_KEYS_FILE" ]]; then
    echo "Extracting root token from $VAULT_KEYS_FILE..."
    ROOT_TOKEN=$(grep "Initial Root Token:" "$VAULT_KEYS_FILE" | awk '{print $4}')
    if [[ -n "$ROOT_TOKEN" ]]; then
        export VAULT_TOKEN="$ROOT_TOKEN"
        echo "Vault token set from vault-keys.txt (overriding any .env value)"
    else
        echo "ERROR: Could not extract root token from $VAULT_KEYS_FILE"
        exit 1
    fi
elif [[ -z "$VAULT_TOKEN" ]]; then
    echo "ERROR: No VAULT_TOKEN set and no vault-keys.txt file found"
    exit 1
fi

# 0) Ensure KV engine exists at "kv/"
vault secrets list -format=json | jq -e '."kv/".type=="kv"' >/dev/null 2>&1 || vault secrets enable -path=kv kv-v2

# 1) Enable JWT auth
vault auth list | grep -q '^jenkins-jwt/' || vault auth enable -path=jenkins-jwt jwt

# 2) Configure JWT verifier
vault write auth/jenkins-jwt/config \
  jwt_validation_pubkeys=@"$PUBKEY_PATH" \
  bound_issuer="$JENKINS_URL" >/dev/null

# 3) Write team-based policies
for team in mobile-developers frontend-developers backend-developers devops-team; do
  vault policy write "$team" "$POLICY_DIR/${team}.hcl"
done
vault policy write jenkins-dev "$POLICY_DIR/jenkins-dev.hcl"  # Keep for job-scoped access

# 4) Create team-based roles (matching Okta group names)
for team in mobile-developers frontend-developers backend-developers devops-team; do
vault write auth/jenkins-jwt/role/${team} -<<JSON
{
  "role_type": "jwt",
  "user_claim": "selected_group",
  "bound_issuer": "$JENKINS_URL",
  "bound_audiences": "vault",
  "bound_claims_type": "string",
  "bound_claims": {
    "env": "dev",
    "selected_group": "$team"
  },
  "token_policies": "$team",
  "token_ttl": "20m",
  "token_max_ttl": "20m",
  "token_no_default_policy": true,
  "token_type": "service"
}
JSON
done

# 5) Child token role for team policies
# Child tokens are issued non-renewable to prevent long-lived extension via renew
vault write auth/token/roles/jenkins-child \
  allowed_policies="mobile-developers,frontend-developers,backend-developers,devops-team,jenkins-dev" \
  orphan=false \
  renewable=false \
  token_type=service \
  token_no_default_policy=true

echo "Vault JWT mount, config, team roles, and policies are set."