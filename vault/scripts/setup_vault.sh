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

# 3) Write the policies
vault policy write jenkins-admin "../policies/jenkins-admin.hcl"
vault policy write jenkins-developers "../policies/jenkins-developers.hcl" 
vault policy write jenkins-readonly "../policies/jenkins-readonly.hcl"
vault policy write jenkins-dev "$POLICY_PATH"  # Keep existing for backward compatibility

# 4) Create multiple roles based on role claim
# Admin role
vault write auth/jenkins-jwt/role/admin-builds -<<'JSON'
{
  "role_type": "jwt",
  "user_claim": "jenkins_job",              
  "bound_issuer": "http://localhost:8080",
  "bound_audiences": "vault",
  
  "bound_claims_type": "string",
  "bound_claims": { 
    "env": "dev",
    "role": "admin"
  },
  
  "token_policies": "jenkins-admin",
  "token_ttl": "20m",
  "token_max_ttl": "20m",
  "token_no_default_policy": true,
  "token_type": "service"
}
JSON

# Developer role  
vault write auth/jenkins-jwt/role/developer-builds -<<'JSON'
{
  "role_type": "jwt",
  "user_claim": "jenkins_job",              
  "bound_issuer": "http://localhost:8080",
  "bound_audiences": "vault",
  
  "bound_claims_type": "string",
  "bound_claims": { 
    "env": "dev",
    "role": "developer"
  },
  
  "token_policies": "jenkins-developers",
  "token_ttl": "20m",
  "token_max_ttl": "20m",
  "token_no_default_policy": true,
  "token_type": "service"
}
JSON

# Readonly role
vault write auth/jenkins-jwt/role/readonly-builds -<<'JSON'
{
  "role_type": "jwt",
  "user_claim": "jenkins_job",              
  "bound_issuer": "http://localhost:8080",
  "bound_audiences": "vault",
  
  "bound_claims_type": "string",
  "bound_claims": { 
    "env": "dev",
    "role": "readonly"
  },
  
  "token_policies": "jenkins-readonly",
  "token_ttl": "20m", 
  "token_max_ttl": "20m",
  "token_no_default_policy": true,
  "token_type": "service"
}
JSON

# Tightened child token auth role - updated for role-based policies
vault write auth/token/roles/jenkins-child \
  allowed_policies="jenkins-admin,jenkins-developers,jenkins-readonly,jenkins-dev" \
  orphan=false \
  renewable=true \
  token_type=service \
  token_no_default_policy=true

echo "Vault JWT mount, config, role, and policy are set."
