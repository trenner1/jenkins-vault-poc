# Vault Team-Based JWT Authen## Comprehensive Testing & Verification

### Manual JWT Authentication Testnical Reference

This document provides **detailed technical implementation** of the team-based JWT authentication system. 

**For setup and overview → See [README.md](README.md)**

## Technical Architecturem-Based JWT Authentication (Enhanced Setup)

This setup provides **streamlined team-based authentication** for Jenkins pipelines using JWT tokens with comprehensive automation and testing.

## Enhanced Features

- **One-Command Setup**: Complete automation from zero to working system
- **Self-Contained Scripts**: Automatic environment handling and token management  
- **Comprehensive Testing**: End-to-end verification of JWT authentication flow
- **Team Isolation Verification**: Proven cross-team access prevention
- **Robust Implementation**: Persistent storage, auto-unseal, proper security

## Team Structure

The system supports four team types, each with isolated secret access:

| Team | Role | Secret Paths | Use Case |
|------|------|-------------|----------|
| **mobile-developers** | `mobile-developers-builds` | `kv/dev/apps/mobile-app/*` | iOS/Android builds, app store credentials |
| **frontend-developers** | `frontend-developers-builds` | `kv/dev/apps/frontend-app/*` | Web builds, CDN credentials, static assets |
| **backend-developers** | `backend-developers-builds` | `kv/dev/apps/backend-service/*` | Databases, APIs, service credentials |
| **devops-team** | `devops-team-builds` | `kv/dev/apps/devops-tools/*` | Infrastructure, monitoring, CI/CD tools |

## Complete Setup & Testing

### 1. Full Environment Setup
```bash
# Start everything with auto-bootstrap
./scripts/start.sh

# Configure JWT authentication and team policies  
./scripts/setup_vault.sh

# Populate team-specific test secrets
./scripts/seed_secret.sh
```

### 2. Test JWT Authentication Flow
```bash
### Manual JWT Authentication Test

**Complete step-by-step authentication flow:**

```bash
# Load environment
source .env

# Generate JWT for mobile team
JWT_TOKEN=$(./scripts/sign_jwt.sh mobile-developers)

# Authenticate with Vault
vault write auth/jenkins-jwt/login role=mobile-developers-builds jwt="${JWT_TOKEN}"
# Returns: token hvs.CAESxxxxx...

# Use team token
export VAULT_TOKEN="hvs.CAESxxxxx..."

# Test team access (should work)
vault kv get kv/dev/apps/mobile-app/example

# Test isolation (should fail with 403)
vault kv get kv/dev/apps/backend-service/example
```

### Multi-Team Testing Script

```bash
# Test all teams systematically
for team in mobile-developers frontend-developers backend-developers devops-team; do
    echo "=== Testing $team ==="
    JWT=$(./scripts/sign_jwt.sh "$team")
    echo "Generated JWT for $team"
    # Use JWT for authentication testing...
done
```

### Automated Verification Scripts

**The system includes comprehensive verification:**

```bash
# Verify no entity churning occurs
./verification/verify-no-churn.sh

# Demo team entity management
./verification/demo-team-entities.sh

# Complete team access demonstration
./verification/comprehensive-team-demo.sh
```

**These scripts verify:**
1. **No Entity Churning**: Same entity/alias reused within teams
2. **Team Isolation**: Teams cannot access other team secrets  
3. **JWT Authentication**: Complete authentication flow works
4. **Policy Enforcement**: Vault policies properly restrict access

## JWT Technical Implementation

### Enhanced JWT Claims Structure
```json
{
  "iss": "http://localhost:8080",           // Jenkins issuer
  "aud": "vault",                           // Vault audience  
  "env": "dev",                             // Environment (REQUIRED)
  "selected_group": "mobile-developers",    // Team identifier
  "jenkins_job": "mobile-app-build",        // Pipeline name
  "build_id": "build-123",                  // Build identifier
  "user": "cli@example.com",                // User context
  "iat": 1234567890,                        // Issued at
  "exp": 1234568490                         // Expires (15 min)
}
```

**Key Enhancement**: The `env: "dev"` claim is **required** and must match the Vault role configuration.

### Vault Authentication Mapping

**JWT → Vault Role → Policy → Secret Access:**

| JWT Claim | Vault Role | Policy Applied | Secret Access |
|-----------|------------|----------------|---------------|
| `selected_group: "mobile-developers"` | `mobile-developers-builds` | `mobile-developers` | `kv/dev/apps/mobile-app/*` |
| `selected_group: "frontend-developers"` | `frontend-developers-builds` | `frontend-developers` | `kv/dev/apps/frontend-app/*` |
| `selected_group: "backend-developers"` | `backend-developers-builds` | `backend-developers` | `kv/dev/apps/backend-service/*` |
| `selected_group: "devops-team"` | `devops-team-builds` | `devops-team` | `kv/dev/apps/devops-tools/*` |

### Authentication Command Syntax

**Correct Authentication Method:**
```bash
# Use 'vault write' NOT 'vault login' for JWT auth
vault write auth/jenkins-jwt/login role=mobile-developers-builds jwt="${JWT_TOKEN}"
```

**Why not `vault login`?**
- `vault login -method=jwt` expects interactive input
- `vault write` allows direct JWT parameter passing
- Our JWT auth is mounted at custom path `jenkins-jwt/`

### Team Policy Details

**Current Implementation (as configured by setup_vault.sh):**

#### Mobile Developers Policy
```hcl
# Team-specific secret access
path "kv/data/dev/apps/mobile-app/*" {
    capabilities = ["read"]
}
path "kv/metadata/dev/apps/mobile-app/*" {
    capabilities = ["read", "list"]
}

# Legacy compatibility paths
path "kv/data/dev/apps/team-mobile-team-pipeline/*" {
    capabilities = ["read"]
}
path "kv/metadata/dev/apps/team-mobile-team-pipeline/*" {
    capabilities = ["read", "list"]
}
```

#### Frontend Developers Policy  
```hcl
# Team-specific secret access
path "kv/data/dev/apps/frontend-app/*" {
    capabilities = ["read"]
}
path "kv/metadata/dev/apps/frontend-app/*" {
    capabilities = ["read", "list"]
}

# Legacy compatibility paths
path "kv/data/dev/apps/team-frontend-team-pipeline/*" {
    capabilities = ["read"]
}
path "kv/metadata/dev/apps/team-frontend-team-pipeline/*" {
    capabilities = ["read", "list"]
}
```

#### Backend Developers Policy
```hcl
# Team-specific secret access
path "kv/data/dev/apps/backend-service/*" {
    capabilities = ["read"]
}
path "kv/metadata/dev/apps/backend-service/*" {
    capabilities = ["read", "list"]
}

# Legacy compatibility paths
path "kv/data/dev/apps/team-backend-team-pipeline/*" {
    capabilities = ["read"]
}
path "kv/metadata/dev/apps/team-backend-team-pipeline/*" {
    capabilities = ["read", "list"]
}
```

#### DevOps Team Policy
```hcl
# Team-specific secret access
path "kv/data/dev/apps/devops-tools/*" {
    capabilities = ["read"]
}
path "kv/metadata/dev/apps/devops-tools/*" {
    capabilities = ["read", "list"]
}

# Cross-team read access (DevOps can read all team secrets)
path "kv/data/dev/apps/*" {
    capabilities = ["read"]
}
path "kv/metadata/dev/apps/*" {
    capabilities = ["read", "list"]
}
```

### Entity Lifecycle & No-Churn Verification

**How Team Entities Work:**
```
1. First JWT auth with selected_group="mobile-developers"
   → Creates entity: mobile-developers
   → Creates alias with team metadata

2. Second JWT auth with same selected_group="mobile-developers"  
   → Reuses SAME entity (no churn!)
   → Updates alias metadata with new JWT claims

3. Different team JWT auth with selected_group="backend-developers"
   → Creates DIFFERENT entity: backend-developers
   → Separate entity per team (logical grouping)
```

**Verification Commands:**
```bash
# Check current entities before auth
vault auth list -detailed
vault list identity/entity/name

# Perform auth, check entities again
vault write auth/jenkins-jwt/login role=mobile-developers-builds jwt="$JWT"
vault list identity/entity/name  # Should show same count + mobile-developers

# Auth again with same team
vault write auth/jenkins-jwt/login role=mobile-developers-builds jwt="$JWT2"  
vault list identity/entity/name  # Count should NOT increase (no churn!)
```

## Usage in Jenkins

### Groovy Pipeline Example
```groovy
pipeline {
    agent any
    
    environment {
        // Set the team based on pipeline context
        SELECTED_TEAM = "${env.JOB_NAME.contains('mobile') ? 'mobile-developers' : 
                         env.JOB_NAME.contains('frontend') ? 'frontend-developers' : 
                         env.JOB_NAME.contains('backend') ? 'backend-developers' : 'devops-team'}"
    }
    
    stages {
        stage('Access Secrets') {
            steps {
                script {
                    // Create JWT with selected_group claim
                    def jwtClaims = [
                        iss: 'http://localhost:8080',
                        aud: 'vault',
                        env: 'dev', 
                        selected_group: env.SELECTED_TEAM,  // This determines team access level
                        jenkins_job: env.JOB_NAME,
                        build_id: env.BUILD_ID,
                        user: env.BUILD_USER_ID ?: 'jenkins',
                        iat: (System.currentTimeMillis() / 1000) as long,
                        exp: ((System.currentTimeMillis() / 1000) + 600) as long
                    ]
                    
                    def jwtToken = createJWT(jwtClaims)
                    
                    // Authenticate to Vault
                    def vaultToken = sh(
                        script: """
                            curl -s -X POST ${VAULT_ADDR}/v1/auth/jenkins-jwt/login \\
                                -d '{"role": "${env.SELECTED_TEAM}", "jwt": "${jwtToken}"}' | \\
                                jq -r '.auth.client_token'
                        """,
                        returnStdout: true
                    ).trim()
                    
                    // Use the token to access team-specific secrets
                    def secret = sh(
                        script: """
                            curl -s -H "X-Vault-Token: ${vaultToken}" \\
                                ${VAULT_ADDR}/v1/kv/data/${env.SELECTED_TEAM}/app-config | \\
                                jq -r '.data.data.api_key'
                        """,
                        returnStdout: true
                    ).trim()
                    
                    echo "Retrieved secret for team: ${env.SELECTED_TEAM}"
                }
            }
        }
    }
}
```

## Team Selection Strategies

### 1. Job Name-Based
```groovy
def selectedTeam = env.JOB_NAME.contains('mobile') ? 'mobile-developers' : 
                   env.JOB_NAME.contains('frontend') ? 'frontend-developers' : 
                   env.JOB_NAME.contains('backend') ? 'backend-developers' : 'devops-team'
```

### 2. Folder-Based
```groovy  
def selectedTeam = env.JOB_NAME.startsWith('mobile/') ? 'mobile-developers' :
                   env.JOB_NAME.startsWith('frontend/') ? 'frontend-developers' :
                   env.JOB_NAME.startsWith('backend/') ? 'backend-developers' : 'devops-team'
```

### 3. Parameter-Based (Recommended for Multi-Team Scenarios)
```groovy
pipeline {
    parameters {
        choice(
            name: 'SELECTED_TEAM',
            choices: ['mobile-developers', 'frontend-developers', 'backend-developers', 'devops-team'],
            description: 'Team context for Vault access'
        )
    }
    // ... use params.SELECTED_TEAM as selected_group
}
```

### 4. Environment-Based
```groovy
// Different teams for different environments
def selectedTeam = env.ENVIRONMENT == 'prod' ? 'devops-team' : 
                   env.JOB_NAME.contains('mobile') ? 'mobile-developers' :
                   env.JOB_NAME.contains('frontend') ? 'frontend-developers' : 'backend-developers'
```

## Benefits

1. **No Entity Churn**: Each team gets exactly one entity, preventing entity proliferation
2. **Team Isolation**: Clear separation between team secrets and access patterns
3. **Simple Configuration**: Single JWT auth mount handles all teams
4. **Audit Trail**: Team context clearly visible in Vault audit logs
5. **Scalable**: Easy to add new teams without changing the authentication mechanism
6. **Cross-Team Support**: Users can work with different teams by selecting appropriate context
7. **Predictable Licensing**: Fixed number of entities (4 total) regardless of user count

## Best Practices

### Team Selection Guidelines
- Use descriptive team names that match your organization: `mobile-developers`, `frontend-developers`, etc.
- Keep team names consistent across different environments (dev/staging/prod)
- Map teams to actual functional groups with specific secret access requirements
- Consider cross-team scenarios where users might need temporary access to other team contexts

### Entity Management  
- Each team gets exactly one entity based on the `selected_group` claim
- Users working within the same team context get the same entity
- This ensures stable entities while providing team-based access control
- The `jenkins_job`, `build_id`, and `user` claims provide detailed audit information

### Secret Organization
- Organize secrets by team: `kv/data/mobile/*`, `kv/data/frontend/*`, etc.
- Use shared paths for common resources: `kv/data/shared/build-tools/*`
- Apply principle of least privilege: teams only access their specific secrets plus necessary shared resources

## Testing

Run the demo script to verify team-based access:
```bash
cd vault/scripts
./demo_role_based_auth.sh
```

This will test all four teams and show the different access patterns in action. You can also run the verification scripts:

```bash
# Test that entities don't churn within teams
./verification/verify-no-churn.sh

# Demonstrate team-based entity creation
./verification/demo-team-entities.sh

# Comprehensive team access demonstration
./verification/comprehensive-team-demo.sh
```

## Current Team Configuration

The system is currently configured with these teams:

- **mobile-developers**: 1 entity for all iOS/Android development work
- **frontend-developers**: 1 entity for all web frontend development work  
- **backend-developers**: 1 entity for all API and backend service work
- **devops-team**: 1 entity for all infrastructure and platform work

Total entities: **4** (one per team, regardless of user count)