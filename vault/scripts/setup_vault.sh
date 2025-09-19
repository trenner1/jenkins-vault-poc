#!/usr/bin/env bash
set -euo pipefail

: "${VAULT_ADDR:?set VAULT_ADDR}"
: "${VAULT_TOKEN:?set VAULT_TOKEN}"

JENKINS_URL="${JENKINS_URL:-http://localhost:8080}"   # override if needed
PUBKEY_PATH="${PUBKEY_PATH:-../../keys/jenkins-oidc.pub}" # adjust if your path differs
POLICY_PATH="${POLICY_PATH:-../policies/jenkins-dev.hcl}"

# 0) Optional: ensure KV engine exists at "kv/"
vault secrets list -format=json | jq -e '."kv/".type=="kv"' >/dev/null 2>&1 || vault secrets enable -path=kv kv-v2

# 1) Enable JWT auth
vault auth list | grep -q '^jenkins-jwt/' || vault auth enable -path=jenkins-jwt jwt

# 2) Configure JWT verifier (using the Jenkins public key)
vault write auth/jenkins-jwt/config \
  jwt_validation_pubkeys=@"$PUBKEY_PATH" \
  bound_issuer="$JENKINS_URL" >/dev/null

# 3) Write the dev policy
vault policy write jenkins-dev "$POLICY_PATH"

# 4) Create the role (licensing-safe: one entity via sub=jenkins-dev)
vault write auth/jenkins-jwt/role/dev-builds -<<'JSON'
{
  "role_type": "jwt",
  "user_claim": "jenkins_job",              
  "bound_issuer": "http://localhost:8080",
  "bound_audiences": "vault",

  "bound_claims_type": "string",
  "bound_claims": { "env": "dev" },

  "token_policies": "jenkins-dev",
  "token_ttl": "20m",
  "token_max_ttl": "20m",
  "token_no_default_policy": true,
  "token_type": "service"
}
JSON


# Tightend child token auth role
vault write auth/token/roles/jenkins-child \
  allowed_policies="jenkins-dev" \
  orphan=false \
  renewable=true \
  token_type=service \
  token_no_default_policy=true


# Optional: widen/narrow where tokens can be used (POC default is open)
vault write auth/jenkins-jwt/role/dev-builds token_bound_cidrs="0.0.0.0/0" >/dev/null

echo "Vault JWT mount, config, role, and policy are set."
