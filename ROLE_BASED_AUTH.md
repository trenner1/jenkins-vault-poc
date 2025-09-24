# Vault Team-Based JWT Authentication

This setup provides team-based authentication for Jenkins pipelines using JWT tokens with different team access levels.

## Overview

The system supports four team types, each with different permissions:

1. **mobile-developers** - Access to mobile app secrets (iOS/Android builds, app store credentials)
2. **frontend-developers** - Access to frontend secrets (build tools, CDN credentials, web assets)
3. **backend-developers** - Access to backend secrets (databases, APIs, service credentials)
4. **devops-team** - Access to infrastructure secrets (cloud resources, monitoring, CI/CD)

## How It Works

### JWT Claims
When creating a JWT token for Vault authentication, include a `selected_group` claim:

```json
{
  "iss": "http://localhost:8080",
  "aud": "vault",
  "env": "dev",
  "selected_group": "backend-developers",  // ← This determines team access level
  "jenkins_job": "user-api-build",
  "build_id": "build-123",
  "user": "alice.smith",
  "iat": 1234567890,
  "exp": 1234568490
}
```

### Vault Roles
The JWT `selected_group` claim maps to these Vault authentication roles:
- `selected_group: "mobile-developers"` → authenticates to `mobile-developers` role → gets `mobile-developers` policy
- `selected_group: "frontend-developers"` → authenticates to `frontend-developers` role → gets `frontend-developers` policy
- `selected_group: "backend-developers"` → authenticates to `backend-developers` role → gets `backend-developers` policy
- `selected_group: "devops-team"` → authenticates to `devops-team` role → gets `devops-team` policy

### Access Patterns

#### Mobile Developers Policy (`mobile-developers` policy)
```hcl
# Access to mobile-specific secrets
path "kv/data/mobile/*" { capabilities = ["create", "read", "update", "delete", "list"] }
path "kv/data/shared/build-tools/*" { capabilities = ["read"] }
path "kv/metadata/mobile/*" { capabilities = ["create", "read", "update", "delete", "list"] }
path "kv/metadata/shared/build-tools/*" { capabilities = ["read", "list"] }
```

#### Frontend Developers Policy (`frontend-developers` policy)  
```hcl
# Access to frontend-specific secrets
path "kv/data/frontend/*" { capabilities = ["create", "read", "update", "delete", "list"] }
path "kv/data/shared/build-tools/*" { capabilities = ["read"] }
path "kv/metadata/frontend/*" { capabilities = ["create", "read", "update", "delete", "list"] }
path "kv/metadata/shared/build-tools/*" { capabilities = ["read", "list"] }
```

#### Backend Developers Policy (`backend-developers` policy)
```hcl
# Access to backend-specific secrets
path "kv/data/backend/*" { capabilities = ["create", "read", "update", "delete", "list"] }
path "kv/data/shared/databases/*" { capabilities = ["read"] }
path "kv/metadata/backend/*" { capabilities = ["create", "read", "update", "delete", "list"] }
path "kv/metadata/shared/databases/*" { capabilities = ["read", "list"] }
```

#### DevOps Team Policy (`devops-team` policy)
```hcl
# Access to infrastructure and shared secrets
path "kv/data/devops/*" { capabilities = ["create", "read", "update", "delete", "list"] }
path "kv/data/shared/*" { capabilities = ["create", "read", "update", "delete", "list"] }
path "kv/metadata/devops/*" { capabilities = ["create", "read", "update", "delete", "list"] }
path "kv/metadata/shared/*" { capabilities = ["create", "read", "update", "delete", "list"] }
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