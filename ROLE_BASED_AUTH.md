# Vault Role-Based JWT Authentication

This setup provides role-based authentication for Jenkins pipelines using JWT tokens with different access levels.

## Overview

The system supports three role types, each with different permissions:

1. **Admin** (`role: "admin"`) - Full access to all secrets
2. **Developer** (`role: "developer"`) - Read/write access to job-scoped secrets 
3. **Readonly** (`role: "readonly"`) - Read-only access to job-scoped secrets

> **Note**: In a production environment, you would replace "admin", "developer", and "readonly" with your actual group names that have identical workloads. For example:
> - `role: "platform-team"` instead of `role: "admin"` 
> - `role: "backend-developers"` instead of `role: "developer"`
> - `role: "qa-automation"` instead of `role: "readonly"`
> 
> The key principle is that all jobs belonging to the same functional group (with identical access requirements) should use the same role value, ensuring they get the same entity and avoiding entity churn.

## How It Works

### JWT Claims
When creating a JWT token for Vault authentication, include a `role` claim:

```json
{
  "iss": "http://localhost:8080",
  "aud": "vault",
  "env": "dev",
  "role": "admin",        // ← This determines access level
  "jenkins_job": "my-job",
  "iat": 1234567890,
  "exp": 1234568490
}
```

### Vault Roles
The JWT `role` claim maps to these Vault authentication roles:
- `role: "admin"` → authenticates to `admin-builds` role → gets `jenkins-admin` policy
- `role: "developer"` → authenticates to `developer-builds` role → gets `jenkins-developers` policy  
- `role: "readonly"` → authenticates to `readonly-builds` role → gets `jenkins-readonly` policy

> **Production Customization**: When implementing this for your organization, create Vault roles and policies that match your team structure:
> ```bash
> # Example: Create roles for actual team names
> vault write auth/jenkins-jwt/role/platform-team-builds bound_claims='{"role": "platform-team"}' token_policies="platform-team-policy"
> vault write auth/jenkins-jwt/role/backend-dev-builds bound_claims='{"role": "backend-developers"}' token_policies="backend-dev-policy"  
> vault write auth/jenkins-jwt/role/qa-builds bound_claims='{"role": "qa-automation"}' token_policies="qa-readonly-policy"
> ```

### Access Patterns

#### Admin Role (`jenkins-admin` policy)
```hcl
# Full access to all secrets
path "kv/data/*" { capabilities = ["create", "read", "update", "delete", "list"] }
path "kv/metadata/*" { capabilities = ["create", "read", "update", "delete", "list"] }
```

#### Developer Role (`jenkins-developers` policy)  
```hcl
# Read/write access to job-scoped secrets only
path "kv/data/jobs/+/*" { capabilities = ["create", "read", "update", "delete"] }
path "kv/metadata/jobs/+/*" { capabilities = ["read", "list"] }
```

#### Readonly Role (`jenkins-readonly` policy)
```hcl
# Read-only access to job-scoped secrets only
path "kv/data/jobs/+/*" { capabilities = ["read"] }
path "kv/metadata/jobs/+/*" { capabilities = ["read", "list"] }
```

## Usage in Jenkins

### Groovy Pipeline Example
```groovy
pipeline {
    agent any
    
    environment {
        // Set the role based on branch, job type, etc.
        VAULT_ROLE = "${env.BRANCH_NAME == 'main' ? 'admin' : 'developer'}"
    }
    
    stages {
        stage('Access Secrets') {
            steps {
                script {
                    // Create JWT with role claim
                    def jwtClaims = [
                        iss: 'http://localhost:8080',
                        aud: 'vault',
                        env: 'dev', 
                        role: env.VAULT_ROLE,  // This determines access level
                        jenkins_job: env.JOB_NAME,
                        iat: (System.currentTimeMillis() / 1000) as long,
                        exp: ((System.currentTimeMillis() / 1000) + 600) as long
                    ]
                    
                    def jwtToken = createJWT(jwtClaims)
                    
                    // Authenticate to Vault
                    def vaultToken = sh(
                        script: """
                            curl -s -X POST ${VAULT_ADDR}/v1/auth/jenkins-jwt/login \\
                                -d '{"role": "${env.VAULT_ROLE}-builds", "jwt": "${jwtToken}"}' | \\
                                jq -r '.auth.client_token'
                        """,
                        returnStdout: true
                    ).trim()
                    
                    // Use the token to access secrets
                    def secret = sh(
                        script: """
                            curl -s -H "X-Vault-Token: ${vaultToken}" \\
                                ${VAULT_ADDR}/v1/kv/data/jobs/${env.JOB_NAME}/db-password | \\
                                jq -r '.data.data.password'
                        """,
                        returnStdout: true
                    ).trim()
                    
                    echo "Retrieved secret: ${secret}"
                }
            }
        }
    }
}
```

## Role Selection Strategies

### 1. Branch-Based
```groovy
def vaultRole = env.BRANCH_NAME == 'main' ? 'admin' : 
               env.BRANCH_NAME == 'develop' ? 'developer' : 'readonly'
```

### 2. Job-Based
```groovy  
def vaultRole = env.JOB_NAME.startsWith('deploy-') ? 'admin' :
               env.JOB_NAME.startsWith('build-') ? 'developer' : 'readonly'
```

### 3. Team-Based (Recommended for Production)
```groovy
// Map Jenkins job folders to team roles
def teamMappings = [
    'platform/': 'platform-team',
    'backend/': 'backend-developers', 
    'frontend/': 'frontend-developers',
    'qa/': 'qa-automation',
    'data/': 'data-engineers'
]

def vaultRole = 'readonly' // default
teamMappings.each { folder, role ->
    if (env.JOB_NAME.startsWith(folder)) {
        vaultRole = role
    }
}
```

### 4. Parameter-Based
```groovy
pipeline {
    parameters {
        choice(
            name: 'VAULT_ACCESS_LEVEL',
            choices: ['qa-automation', 'backend-developers', 'platform-team'],
            description: 'Team role for Vault access'
        )
    }
    // ... use params.VAULT_ACCESS_LEVEL as role
}
```

## Benefits

1. **No Entity Churn**: All users with the same `jenkins_job` claim get the same entity/alias regardless of role
2. **Flexible Access Control**: Same entity can have different access levels based on context
3. **Simple Configuration**: Single JWT auth mount handles all roles
4. **Audit Trail**: Different roles clearly visible in Vault audit logs
5. **Team-Based Security**: Map roles to actual organizational teams with identical workload requirements
6. **Scalable**: Easy to add new teams/roles without changing the authentication mechanism

## Best Practices

### Role Naming Convention
- Use descriptive team/group names: `platform-team`, `backend-developers`, `qa-automation`
- Avoid generic terms like `admin`, `user`, `developer` in production
- Match your organization's team structure and naming conventions
- Keep role names consistent across different environments (dev/staging/prod)

### Entity Management  
- Jobs with identical access requirements should use the same role claim
- The `jenkins_job` claim creates the entity - keep this unique per logical job
- The `role` claim only affects policy assignment, not entity creation
- This ensures stable entities while allowing flexible access control

## Testing

Run the test script to verify role-based access:
```bash
cd vault/scripts
python3 test_role_auth.py
```

This will test all three roles and show the different access patterns in action.