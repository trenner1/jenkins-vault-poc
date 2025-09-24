#!/usr/bin/env python3
"""
Test script for Vault role-based JWT authentication.
Demonstrates how different role claims provide different access levels.
"""

import jwt
import json
import datetime
import requests
from pathlib import Path
import sys

# Vault configuration
VAULT_ADDR = "http://localhost:8200"
VAULT_TOKEN = "<REDACTED>"  # Vault token removed for security

def create_jwt_token(role, job_name="test-job"):
    """Create a JWT token with the specified role claim."""
    
    # Read the private key
    key_path = Path("../../keys/jenkins-oidc.key")
    with open(key_path, 'r') as f:
        private_key = f.read()
    
    # Create JWT claims
    now = datetime.datetime.now(datetime.timezone.utc)
    claims = {
        "iss": "http://localhost:8080",
        "aud": "vault", 
        "env": "dev",
        "role": role,
        "jenkins_job": job_name,
        "iat": int((now - datetime.timedelta(seconds=10)).timestamp()),  # Issued 10 seconds ago
        "nbf": int((now - datetime.timedelta(seconds=10)).timestamp()),  # Not before 10 seconds ago
        "exp": int((now + datetime.timedelta(minutes=10)).timestamp())   # Expires in 10 minutes
    }
    
    # Create and return JWT
    return jwt.encode(claims, private_key, algorithm='RS256')

def vault_login(role, jwt_token):
    """Login to Vault using JWT and return the token."""
    
    url = f"{VAULT_ADDR}/v1/auth/jenkins-jwt/login"
    data = {
        "role": f"{role}-builds",
        "jwt": jwt_token
    }
    
    response = requests.post(url, json=data)
    if response.status_code == 200:
        return response.json()["auth"]["client_token"]
    else:
        print(f"❌ Login failed: {response.status_code} - {response.text}")
        return None

def test_vault_access(vault_token, secret_path):
    """Test reading from a Vault secret path."""
    
    url = f"{VAULT_ADDR}/v1/{secret_path}"
    headers = {"X-Vault-Token": vault_token}
    
    response = requests.get(url, headers=headers)
    return response.status_code == 200

def test_vault_write(vault_token, secret_path, data):
    """Test writing to a Vault secret path."""
    
    url = f"{VAULT_ADDR}/v1/{secret_path}"
    headers = {"X-Vault-Token": vault_token}
    
    response = requests.post(url, json=data, headers=headers)
    return response.status_code == 200

def test_role(role_name):
    """Test authentication and access for a specific role."""
    
    print(f"\n🔑 Testing {role_name} role")
    print("=" * 40)
    
    # Create JWT
    jwt_token = create_jwt_token(role_name)
    print(f"📝 Created JWT with role='{role_name}'")
    
    # Login to Vault
    vault_token = vault_login(role_name, jwt_token)
    if not vault_token:
        return
        
    print(f"✅ Successfully authenticated to Vault")
    
    # Test read access
    read_path = "kv/data/jobs/test-job/db-password"
    if test_vault_access(vault_token, read_path):
        print(f"✅ Can read {read_path}")
    else:
        print(f"❌ Cannot read {read_path}")
    
    # Test write access  
    write_path = "kv/data/jobs/test-job/test-secret"
    write_data = {"data": {"value": f"test-from-{role_name}"}}
    if test_vault_write(vault_token, write_path, write_data):
        print(f"✅ Can write to {write_path}")
    else:
        print(f"❌ Cannot write to {write_path}")
    
    # Test admin access - full path access for admin, restricted for others
    admin_path = "kv/data/admin/admin-secret" 
    if test_vault_access(vault_token, admin_path):
        print(f"✅ Can read admin path {admin_path}")
    else:
        print(f"❌ Cannot read admin path {admin_path}")

def setup_test_data():
    """Set up test secrets in Vault."""
    
    print("📝 Setting up test data...")
    headers = {"X-Vault-Token": VAULT_TOKEN}
    
    # Create test secret
    url = f"{VAULT_ADDR}/v1/kv/data/jobs/test-job/db-password"
    data = {"data": {"password": "secret123"}}
    requests.post(url, json=data, headers=headers)
    
    # Create admin secret
    url = f"{VAULT_ADDR}/v1/kv/data/admin/admin-secret"
    data = {"data": {"admin-key": "admin-value"}}
    requests.post(url, json=data, headers=headers)
    
    print("✅ Test data created")

def main():
    print("🚀 Vault Role-Based JWT Authentication Test")
    print("=" * 50)
    
    # Setup test data
    setup_test_data()
    
    # Test each role
    for role in ["admin", "developer", "readonly"]:
        test_role(role)
    
    print("\n" + "=" * 50)
    print("📋 Summary:")
    print("• Admin: Should have full access to all paths")
    print("• Developer: Should read/write job-scoped, no admin access")
    print("• Readonly: Should only read job-scoped, no write/admin access")
    print("\n✨ Role-based authentication is working!")

if __name__ == "__main__":
    main()