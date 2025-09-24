#!/usr/bin/env bash
set -euo pipefail

echo "=== Vault Team-Based JWT Authentication Demo ==="
echo

# Source environment variables if .env exists
if [ -f "../../.env" ]; then
    source "../../.env"
fi

# Set up environment
export VAULT_ADDR=http://localhost:8200
: "${VAULT_TOKEN:?VAULT_TOKEN must be set (source .env file)}"

# Function to create and test a JWT with different team claims
test_jwt_team() {
  local team_claim="$1"
  local expected_policy="$2"
  local job_name="${3:-test-job}"
  
  echo "Testing JWT with selected_group='$team_claim'"
  
  # Create JWT with the specified team claim
  jwt_token=$(/Users/trevorrenner/projects/jenkins-vault-poc/.venv/bin/python -c "
import sys, json, jwt, datetime
from pathlib import Path

# Create the claims directly
claims = {
    'selected_group': '$team_claim',
    'jenkins_job': '$job_name',
    'build_id': 'demo-test-' + str(int(datetime.datetime.now().timestamp())),
    'user': 'demo.user',
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
  vault_token=$(vault write -field=token auth/jenkins-jwt/login role="$team_claim" jwt="$jwt_token")
  
  if [ -n "$vault_token" ]; then
    echo "Authentication successful!"
    
    # Check token info
    echo "Token info:"
    VAULT_TOKEN="$vault_token" vault token lookup -format=json 2>/dev/null | jq -r '.data | "  Policies: \(.policies | join(", "))\n  TTL: \(.ttl)s\n  Entity ID: \(.entity_id)"' || echo "  (Token info lookup requires additional permissions)"
    
    # Test access to team-specific secret path
    case "$team_claim" in
      "mobile-developers")
        test_path="kv/dev/apps/mobile-app/config"
        write_path="kv/dev/apps/mobile-app/test-secret"
        ;;
      "frontend-developers")
        test_path="kv/dev/apps/frontend-app/config"
        write_path="kv/dev/apps/frontend-app/test-secret"
        ;;
      "backend-developers")
        test_path="kv/dev/apps/backend-service/config"
        write_path="kv/dev/apps/backend-service/test-secret"
        ;;
      "devops-team")
        test_path="kv/dev/apps/devops-tools/config"
        write_path="kv/dev/apps/devops-tools/test-secret"
        ;;
    esac
    
    echo "Testing access to $test_path:"
    if VAULT_TOKEN="$vault_token" vault kv get "$test_path" 2>/dev/null; then
      echo "Read access successful"
    else
      echo "Read access denied (may not exist yet)"
    fi
    
    # Test write access to team path
    echo "Testing write access to $write_path:"
    if VAULT_TOKEN="$vault_token" vault kv put "$write_path" value="test-from-$team_claim" 2>/dev/null; then
      echo "Write access successful"
    else
      echo "Write access denied"
    fi
    
  else
    echo "Authentication failed!"
  fi
  
  echo "----------------------------------------"
  echo
}

# Set up some test data first
echo "📝 Setting up test data..."
vault kv put kv/dev/apps/mobile-app/config api_key="mobile-secret-123" >/dev/null 2>&1 || true
vault kv put kv/dev/apps/frontend-app/config api_key="frontend-secret-456" >/dev/null 2>&1 || true
vault kv put kv/dev/apps/backend-service/config api_key="backend-secret-789" >/dev/null 2>&1 || true
vault kv put kv/dev/apps/devops-tools/config api_key="devops-secret-000" >/dev/null 2>&1 || true
echo

# Test each team
test_jwt_team "mobile-developers" "mobile-developers" "mobile-app-build"
test_jwt_team "frontend-developers" "frontend-developers" "frontend-app-build" 
test_jwt_team "backend-developers" "backend-developers" "backend-service-build"
test_jwt_team "devops-team" "devops-team" "infrastructure-deploy"

echo "=== Demo Complete ==="
echo
echo "Summary:"
echo "• mobile-developers: Access to mobile app secrets and shared build tools"
echo "• frontend-developers: Access to frontend secrets and shared build tools"  
echo "• backend-developers: Access to backend secrets and shared databases"
echo "• devops-team: Access to infrastructure secrets and all shared resources"
echo
echo "To use in Jenkins, set the 'selected_group' claim in your JWT to one of:"
echo "  - 'mobile-developers' for mobile team access"
echo "  - 'frontend-developers' for frontend team access"
echo "  - 'backend-developers' for backend team access"
echo "  - 'devops-team' for infrastructure/platform access"