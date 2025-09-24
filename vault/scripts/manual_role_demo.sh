#!/usr/bin/env bash
set -euo pipefail

echo "🔐 Manual Role Selection Demo"
echo "============================="
echo

export VAULT_ADDR=http://localhost:8200

# Function to create a JWT for a specific role
create_jwt_for_role() {
    local role="$1"
    local job_name="$2"
    
    echo "📝 Creating JWT for role: $role, job: $job_name"
    
    jwt_token=$(/Users/trevorrenner/projects/jenkins-vault-poc/.venv/bin/python -c "
import jwt, datetime
from pathlib import Path

# Create claims with specific role
claims = {
    'role': '$role',           # This determines which Vault role you can use
    'jenkins_job': '$job_name', # This determines the entity/alias
    'iss': 'http://localhost:8080',
    'aud': 'vault',
    'env': 'dev',
    'iat': int((datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=10)).timestamp()),
    'exp': int((datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(minutes=10)).timestamp())
}

# Read private key
key_path = Path('../../keys/jenkins-oidc.key')
with open(key_path, 'r') as f:
    private_key = f.read()

# Create JWT
token = jwt.encode(claims, private_key, algorithm='RS256')
print(token)
")
    
    echo "✅ JWT created with role claim: $role"
    echo "   Token: ${jwt_token:0:20}..."
    echo
    
    # Now login using the JWT
    echo "🔑 Logging in to Vault with role: ${role}-builds"
    vault_token=$(vault write -field=token auth/jenkins-jwt/login \
        role="${role}-builds" \
        jwt="$jwt_token" 2>/dev/null)
    
    if [ -n "$vault_token" ]; then
        echo "✅ Login successful!"
        echo "   Vault token: ${vault_token:0:20}..."
        
        # Test what this token can do
        echo "🧪 Testing access with this token..."
        
        # Try to read a secret
        if VAULT_TOKEN="$vault_token" vault kv get kv/jobs/$job_name/db-password >/dev/null 2>&1; then
            echo "   ✅ Can read job secrets"
        else
            echo "   ❌ Cannot read job secrets"
        fi
        
        # Try to write a secret
        if VAULT_TOKEN="$vault_token" vault kv put kv/jobs/$job_name/test-secret value="test-$role" >/dev/null 2>&1; then
            echo "   ✅ Can write job secrets"
        else
            echo "   ❌ Cannot write job secrets"
        fi
        
        # Try to read admin secrets
        if VAULT_TOKEN="$vault_token" vault kv get kv/admin/admin-secret >/dev/null 2>&1; then
            echo "   ✅ Can read admin secrets"
        else
            echo "   ❌ Cannot read admin secrets"
        fi
        
    else
        echo "❌ Login failed!"
    fi
    
    echo
    echo "----------------------------------------"
    echo
}

# Set up test data
echo "📋 Setting up test data..."
vault kv put kv/jobs/demo-job/db-password password="demo123" >/dev/null 2>&1 || true
vault kv put kv/admin/admin-secret admin-key="admin-value" >/dev/null 2>&1 || true
echo "✅ Test data ready"
echo

# Show available roles
echo "📋 Available roles in Vault:"
vault list auth/jenkins-jwt/role | grep -v "^Keys" | grep -v "^----" | while read role; do
    echo "   • $role"
done
echo

echo "🎯 Now demonstrating manual role selection:"
echo

# Demo each role
create_jwt_for_role "admin" "demo-job"
create_jwt_for_role "developer" "demo-job" 
create_jwt_for_role "readonly" "demo-job"

echo "🎉 Demo complete!"
echo
echo "📚 Summary:"
echo "To specify a role:"
echo "1. Create JWT with 'role' claim set to: admin, developer, or readonly"
echo "2. Login to Vault role: {role}-builds (e.g., admin-builds, developer-builds, readonly-builds)"
echo "3. The role claim in JWT MUST match the Vault role you're logging into"
echo
echo "💡 Key insight: Same jenkins_job = same entity, different role = different access"