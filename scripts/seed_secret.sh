#!/usr/bin/env bash
# Seed secrets script for Jenkins-Vault POC
# Creates or updates all secrets used by the team-based authentication system
set -euo pipefail

## Load environment variables from a .env file (search multiple likely locations)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_PATHS=("${PWD}/.env" "${SCRIPT_DIR}/.env" "${SCRIPT_DIR}/../.env")
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

# Set default VAULT_ADDR if not set
if [[ -z "${VAULT_ADDR:-}" ]]; then
    echo "Setting default VAULT_ADDR=http://localhost:8200"
    export VAULT_ADDR="http://localhost:8200"
fi

# Resolve repo root and extract root token from vault-keys.txt if needed
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VAULT_KEYS_FILE="${VAULT_KEYS_FILE:-$REPO_ROOT/vault-keys.txt}"

# Extract root token from vault-keys.txt (prioritize over .env file)
if [[ -f "$VAULT_KEYS_FILE" ]]; then
    echo "Extracting root token from $VAULT_KEYS_FILE..."
    ROOT_TOKEN=$(grep "Initial Root Token:" "$VAULT_KEYS_FILE" | awk '{print $4}')
    if [[ -n "$ROOT_TOKEN" ]]; then
        export VAULT_TOKEN="$ROOT_TOKEN"
        echo "Vault token set from vault-keys.txt"
    else
        echo "ERROR: Could not extract root token from $VAULT_KEYS_FILE"
        exit 1
    fi
elif [[ -z "${VAULT_TOKEN:-}" ]]; then
    echo "ERROR: No VAULT_TOKEN set and no vault-keys.txt file found"
    exit 1
fi

echo "Seeding secrets for Jenkins-Vault POC..."

# Core team application secrets (used by Jenkins pipeline)
echo "Creating team application secrets..."

# Mobile team secrets  
vault kv put kv/dev/apps/mobile-app/example \
  demo_key="mobile_example_value" \
  team="mobile-developers" \
  api_endpoint="https://mobile-api.company.com" \
  environment="development" \
  last_updated="$(date -Iseconds)"

vault kv put kv/dev/apps/mobile-app/config \
  api_key="mobile-secret-123" \
  bundle_id="com.company.mobile" \
  provisioning_profile="mobile-dev-profile"

# Frontend team secrets
vault kv put kv/dev/apps/frontend-app/example \
  demo_key="frontend_example_value" \
  team="frontend-developers" \
  api_endpoint="https://frontend-api.company.com" \
  environment="development" \
  last_updated="$(date -Iseconds)"

vault kv put kv/dev/apps/frontend-app/config \
  api_key="frontend-secret-456" \
  cdn_url="https://frontend-cdn.company.com" \
  build_config="production"

# Backend team secrets
vault kv put kv/dev/apps/backend-service/example \
  demo_key="backend_example_value" \
  team="backend-developers" \
  api_endpoint="https://backend-api.company.com" \
  environment="development" \
  last_updated="$(date -Iseconds)"

vault kv put kv/dev/apps/backend-service/config \
  api_key="backend-secret-789" \
  database_url="postgresql://backend-db.company.com:5432/app" \
  redis_url="redis://backend-cache.company.com:6379"

# DevOps team secrets
vault kv put kv/dev/apps/devops-tools/example \
  demo_key="devops_example_value" \
  team="devops-team" \
  api_endpoint="https://devops-api.company.com" \
  environment="development" \
  last_updated="$(date -Iseconds)"

vault kv put kv/dev/apps/devops-tools/config \
  api_key="devops-secret-000" \
  monitoring_url="https://monitoring.company.com" \
  deployment_key="devops-deploy-key"

# Bazel demo compatibility secrets (legacy team pipeline paths)
echo "Creating Bazel demo compatibility secrets..."

vault kv put kv/dev/apps/team-mobile-team-pipeline/legacy \
  legacy_mobile_key="mobile-legacy-123" \
  team="mobile-team" \
  purpose="bazel-demo-compatibility"

vault kv put kv/dev/apps/team-backend-team-pipeline/legacy \
  legacy_backend_key="backend-legacy-456" \
  team="backend-team" \
  purpose="bazel-demo-compatibility"

vault kv put kv/dev/apps/team-frontend-team-pipeline/legacy \
  legacy_frontend_key="frontend-legacy-789" \
  team="frontend-team" \
  purpose="bazel-demo-compatibility"

echo ""
echo "All secrets seeded successfully!"
echo ""
echo "Summary:"
echo "   Core team apps: mobile-app, frontend-app, backend-service, devops-tools"
echo "   Legacy paths: team-*-team-pipeline (Bazel compatibility)"
echo "   Total paths: $(vault kv list kv/dev/apps | wc -l) application directories"
echo ""
echo "Ready for Jenkins pipeline and team-based authentication demos!"
