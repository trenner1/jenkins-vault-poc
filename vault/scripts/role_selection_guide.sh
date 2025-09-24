#!/usr/bin/env bash
set -euo pipefail

echo "🎯 Manual Role Selection Guide"
echo "=============================="
echo

export VAULT_ADDR=http://localhost:8200

echo "Available roles:"
echo "• admin     - Full access to all secrets"
echo "• developer - Read/write access to job-scoped secrets" 
echo "• readonly  - Read-only access to job-scoped secrets"
echo

echo "To manually test each role:"
echo

# Function to show how to create JWT and login for a specific role
show_role_usage() {
    local role="$1"
    local description="$2"
    
    echo "📋 For $role role ($description):"
    echo
    echo "1. Create JWT with role claim:"
    cat << EOF
   jwt_token=\$(/path/to/venv/bin/python -c "
import jwt, datetime
from pathlib import Path

claims = {
    'role': '$role',                    # ← Role you want
    'jenkins_job': 'my-demo-job',       # ← Your job name  
    'iss': 'http://localhost:8080',
    'aud': 'vault',
    'env': 'dev',
    'iat': int((datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=10)).timestamp()),
    'exp': int((datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(minutes=10)).timestamp())
}

key_path = Path('keys/jenkins-oidc.key')
with open(key_path, 'r') as f:
    private_key = f.read()

token = jwt.encode(claims, private_key, algorithm='RS256')
print(token)
")
EOF
    echo
    echo "2. Login to Vault:"
    echo "   vault write auth/jenkins-jwt/login role=\"$role-builds\" jwt=\"\$jwt_token\""
    echo
    echo "3. This gives you a token with '$description' permissions"
    echo
    echo "----------------------------------------"
    echo
}

show_role_usage "admin" "full access"
show_role_usage "developer" "job-scoped read/write"  
show_role_usage "readonly" "job-scoped read-only"

echo "🔑 Key Points:"
echo "• The JWT 'role' claim determines which Vault role you can authenticate to"
echo "• You must login to the matching Vault role: {role}-builds"
echo "• Same 'jenkins_job' claim = same entity (no entity churn)"
echo "• Different 'role' claim = different access level"
echo
echo "Example: JWT with role='developer' can only login to 'developer-builds' role"
echo

echo "🧪 Want to test? Run:"
echo "  cd /Users/trevorrenner/projects/jenkins-vault-poc/vault/scripts"
echo "  ./manual_role_demo.sh"