#!/usr/bin/env bash
set -euo pipefail

: "${VAULT_ADDR:?set VAULT_ADDR}"
: "${VAULT_TOKEN:?set VAULT_TOKEN}"

JENKINS_URL="${JENKINS_URL:-http://localhost:8080}"
PUBKEY_PATH="${PUBKEY_PATH:-../../keys/jenkins-oidc.pub}"
POLICY_DIR="${POLICY_DIR:-../policies}"

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

# 4) Create team-based roles
for team in mobile-developers frontend-developers backend-developers devops-team; do
vault write auth/jenkins-jwt/role/${team}-builds -<<JSON
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
vault write auth/token/roles/jenkins-child \
  allowed_policies="mobile-developers,frontend-developers,backend-developers,devops-team,jenkins-dev" \
  orphan=false \
  renewable=true \
  token_type=service \
  token_no_default_policy=true

echo "Vault JWT mount, config, team roles, and policies are set."