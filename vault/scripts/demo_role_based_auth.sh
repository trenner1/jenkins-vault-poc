#!/bin/bash
# Example: How to create JWTs with different role claims

set -euo pipefail

PRIVATE_KEY="../../keys/jenkins-oidc.key"

# Helper function to create base64url encoded strings
b64url() { openssl base64 -A | tr "+/" "-_" | tr -d "="; }

# Create JWT header
printf '{"alg":"RS256","typ":"JWT","kid":"jenkins-dev-key-1"}' > /tmp/h.json
H=$(b64url < /tmp/h.json)

# Function to create JWT with specific role
create_jwt_with_role() {
    local role=$1
    local user=$2
    local job=$3
    
    echo "Creating JWT for $role access..."
    
    IAT=$(date +%s)
    EXP=$((IAT+900))
    BUILD_ID="demo-$(date +%s)"
    
    # Create payload with role claim
    jq -n \
      --arg iss "http://localhost:8080" \
      --arg sub "jenkins-dev" \
      --arg aud "vault" \
      --arg env "dev" \
      --arg role "$role" \
      --arg job "$job" \
      --arg build "$BUILD_ID" \
      --arg user "$user" \
      --argjson iat "$IAT" \
      --argjson exp "$EXP" \
      '{iss:$iss,sub:$sub,aud:$aud,iat:$iat,exp:$exp,env:$env,role:$role,jenkins_job:$job,build_id:$build,user:$user}' > /tmp/p.json
    
    P=$(b64url < /tmp/p.json)
    
    # Sign the JWT
    SIG=$(printf "%s.%s" "$H" "$P" | openssl dgst -sha256 -sign "$PRIVATE_KEY" -binary | b64url)
    JWT_TOKEN="$H.$P.$SIG"
    
    echo "JWT Payload:"
    cat /tmp/p.json | jq .
    echo ""
    
    # Test authentication with the appropriate role
    local vault_role
    case $role in
        "admin") vault_role="admin-builds" ;;
        "developer") vault_role="developer-builds" ;;
        "readonly") vault_role="readonly-builds" ;;
        *) echo "Unknown role: $role"; return 1 ;;
    esac
    
    echo "Authenticating with Vault role: $vault_role"
    vault write auth/jenkins-jwt/login role="$vault_role" jwt="$JWT_TOKEN" -format=json | jq -r '.auth.client_token'
    echo ""
}

echo "=== JWT Role-based Authentication Demo ==="
echo ""

# Set Vault address
export VAULT_ADDR="http://localhost:8200"

echo "1. Admin access (full CRUD permissions):"
ADMIN_TOKEN=$(create_jwt_with_role "admin" "admin.user" "deploy-pipeline")

echo "2. Developer access (read/write to job-scoped secrets):"
DEV_TOKEN=$(create_jwt_with_role "developer" "dev.user" "build-pipeline")

echo "3. Readonly access (read-only to job-scoped secrets):"
READONLY_TOKEN=$(create_jwt_with_role "readonly" "readonly.user" "test-pipeline")

echo "✅ All role-based authentications successful!"
echo ""
echo "Now you can use these tokens with different permission levels:"
echo "  Admin token:    $ADMIN_TOKEN"
echo "  Developer token: $DEV_TOKEN" 
echo "  Readonly token:  $READONLY_TOKEN"