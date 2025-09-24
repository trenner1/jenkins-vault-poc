#!/usr/bin/env bash
# Seed secrets script for Jenkins-Vault POC
# Creates or updates all secrets used by the team-based authentication system
set -euo pipefail

: "${VAULT_ADDR:?set VAULT_ADDR}"
: "${VAULT_TOKEN:?set VAULT_TOKEN}"

echo "🌱 Seeding secrets for Jenkins-Vault POC..."

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
echo "✅ All secrets seeded successfully!"
echo ""
echo "📋 Summary:"
echo "   Core team apps: mobile-app, frontend-app, backend-service, devops-tools"
echo "   Legacy paths: team-*-team-pipeline (Bazel compatibility)"
echo "   Total paths: $(vault kv list kv/dev/apps | wc -l) application directories"
echo ""
echo "🎯 Ready for Jenkins pipeline and team-based authentication demos!"
