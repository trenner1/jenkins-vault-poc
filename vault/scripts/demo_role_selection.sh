#!/usr/bin/env bash
set -euo pipefail

echo "=== Vault Role-Based JWT Authentication Demo ==="
echo

# Set up environment
export VAULT_ADDR=http://localhost:8200

# Function to create and test a JWT with different role claims
test_jwt_role() {
  local role_claim="$1"
  local expected_policy="$2"
  local job_name="${3:-test-job}"
  
  echo "Testing JWT with role='$role_claim'"
  
  # Create JWT with the specified role claim
  jwt_token=$(/Users/trevorrenner/projects/jenkins-vault-poc/.venv/bin/python -c "
import sys, json, jwt, datetime
from pathlib import Path

# Create the claims directly
claims = {
    'role': '$role_claim',
    'jenkins_job': '$job_name',
    'iss': 'http://localhost:8080',
    'aud': 'vault',
    'env': 'dev',
    'exp': int((datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(minutes=10)).timestamp()),
    'iat': int((datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=10)).timestamp())
}

# Read private key
key_path = Path('../../keys/jenkins-oidc.key')
with open(key_path, 'r') as f:
    private_key = f.read()

# Create JWT
token = jwt.encode(claims, private_key, algorithm='RS256')
print(token)
")

  # Login with the JWT
  vault_token=$(vault write -field=token auth/jenkins-jwt/login role="${role_claim}-builds" jwt="$jwt_token")
  
  if [ -n "$vault_token" ]; then
    echo "Authentication successful!"
    
    # Check token info
    echo "Token info:"
    VAULT_TOKEN="$vault_token" vault token lookup -format=json 2>/dev/null | jq -r '.data | "  Policies: \(.policies | join(", "))\n  TTL: \(.ttl)s\n  Entity ID: \(.entity_id)"' || echo "  (Token info lookup requires additional permissions)"
    
    # Test access to a secret path
    echo "Testing access to kv/jobs/$job_name/db-password:"
    if VAULT_TOKEN="$vault_token" vault kv get kv/jobs/$job_name/db-password 2>/dev/null; then
      echo "Read access successful"
    else
      echo "Read access denied"
    fi
    
    # Test write access 
    echo "Testing write access to kv/jobs/$job_name/test-secret:"
    if VAULT_TOKEN="$vault_token" vault kv put kv/jobs/$job_name/test-secret value="test-from-$role_claim" 2>/dev/null; then
      echo " Write access successful"
    else
      echo " Write access denied"
    fi
    
  else
    echo " Authentication failed!"
  fi
  
  echo "----------------------------------------"
  echo
}

# Set up some test data first
echo "📝 Setting up test data..."
vault kv put kv/jobs/test-job/db-password password="secret123" >/dev/null 2>&1 || true
echo

# Test each role
test_jwt_role "admin" "jenkins-admin" "test-job"
test_jwt_role "developer" "jenkins-developers" "test-job" 
test_jwt_role "readonly" "jenkins-readonly" "test-job"

echo "=== Demo Complete ==="
echo
echo "Summary:"
echo "• Admin role: Full CRUD access to all secrets"
echo "• Developer role: Read/write access to job-scoped secrets"  
echo "• Readonly role: Read-only access to job-scoped secrets"
echo
echo "To use in Jenkins, set the 'role' claim in your JWT to one of:"
echo "  - 'admin' for full access"
echo "  - 'developer' for job-scoped read/write"
echo "  - 'readonly' for job-scoped read-only"