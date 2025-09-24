# Jenkins ↔ Vault JWT Authentication POC

A production-ready proof of concept demonstrating **team-based JWT authentication** between Jenkins and HashiCorp Vault with **logical workload grouping**.

## What This POC Proves

- **Zero Entity Churning**: Same entity/alias reused across team member logins  
- **Logical Grouping**: Entity count scales with teams, organizing identical workloads efficiently  
- **Production Ready**: Raft storage, proper policies, automation, persistence  
- **Secure**: Job-scoped access with dynamic policy templating  
- **Scalable**: Supports large monorepos with multiple development teams  

**Verified**: Real JWT authentication tested with entity ID tracking - **no churning detected**.

## Key Features

- **JWT Authentication**: Jenkins → Vault using self-signed JWTs
- **Team-Based Access**: One entity per team groups identical workloads logically
- **No Entity Churning**: Proven entity/alias reuse within teams
- **Job-Scoped Secrets**: Dynamic policy templating based on pipeline context
- **Persistent Data**: Survives container restarts with auto-unseal
- **Production Ready**: Raft storage, proper policies, automation scripts

## Architecture Overview

### Team-Based Entity Model
```
Mobile Team         →  Entity: mobile-developers      →  Secrets: kv/dev/apps/mobile-app/*
Frontend Team       →  Entity: frontend-developers    →  Secrets: kv/dev/apps/frontend-app/*
Backend Team        →  Entity: backend-developers     →  Secrets: kv/dev/apps/backend-service/*
DevOps Team         →  Entity: devops-team            →  Secrets: kv/dev/apps/devops-tools/*
```

**Benefits:**
- **No Churning**: Same entity reused by all team members
- **Logical Organization**: Entity count = number of teams (groups identical workloads)
- **Secure**: Job-scoped access via policy templating
- **Scalable**: Supports large organizations with multiple teams

## Comparison with Other Approaches

| Approach | Entities Created | Workload Organization | Team Isolation | Complexity |
|----------|------------------|------------------|----------------|------------|
| **Per Developer** | 1 per developer | High | Excellent | Medium |
| **Single Shared** | 1 total | Minimal | None | Low |
| **Per Team (This POC)** | 1 per team | Low | Good | Medium |

### Why Team-Based is Optimal:
- **Logical Grouping**: Groups identical workloads by team function
- **Security**: Natural isolation boundaries align with org structure  
- **Scalability**: Linear growth with workload types rather than individual users
- **Management**: Easier to audit and manage team-based access

## Quick Start

### Start Everything
```bash
./scripts/start.sh
```
This will:
- Start Docker containers (Jenkins + Vault)
- Auto-unseal Vault with stored keys
- Show status and access URLs

### Stop Everything  
```bash
./scripts/stop.sh
```
Data is preserved in `./data/` directory.

### Manual Vault Unseal (if needed)
```bash
./scripts/unseal-vault.sh
```

## Access URLs
- **Jenkins**: http://localhost:8080
- **Vault UI**: http://localhost:8200 
- **Root Token**: `<found in vault-keys.txt>` (stored in `vault-keys.txt`)

## Data Persistence
- **Jenkins**: `./data/jenkins_home/` (preserves all Jenkins config)
- **Vault**: `./data/vault/data/` (Raft storage, preserves secrets)
- **Keys**: `./vault-keys.txt` (WARNING: Keep secure - contains unseal keys!)

## Vault Configuration
- **Auth Method**: JWT (`jenkins-jwt/`)
- **Policy**: One per team:
    - `mobile-developers.hcl`
    - `frontend-developers.hcl`
    - `backend-developers.hcl`
    - `devops-team.hcl`
- **Role**: One per team (e.g., `mobile-developers`, `frontend-developers`, `backend-developers`, `devops-team`) for Jenkins pipelines
- **Entity**: One per team (e.g., `mobile-developers`, `frontend-developers`, `backend-developers`, `devops-team`)
- **JWT Claims**: `selected_group` field set to team name (e.g., `selected_group: "mobile-developers"`)
- **Secrets**: Seeded test data in team-specific paths (e.g., `kv/dev/apps/mobile-pipeline/*`)

## Verification & Testing

### Verify No Entity Churning
```bash
# Run comprehensive verification test
./verification/verify-no-churn.sh

# Show team-based entity management concepts
./verification/demo-team-entities.sh

# Complete team access demonstration
./verification/comprehensive-team-demo.sh
```

The verification scripts:
1. Record current entity/alias state
2. Perform real JWT authentication with team-based claims
3. Verify same entity/alias IDs are reused within teams
4. **Prove no churning occurs within team contexts**

### Test Pipeline Integration
1. Access Jenkins: http://localhost:8080
2. Run `sample-pipeline` job
3. Watch JWT → Vault authentication in action
4. Verify secret access in job logs

## Configuration Details

### JWT Claims Structure
```json
{
  "iss": "http://localhost:8080",       // Jenkins issuer
  "aud": "vault",                       // Vault audience
  "env": "dev",                         // Environment
  "selected_group": "mobile-developers"|"frontend-developers"|"backend-developers"|"devops-team", // Team identifier
  "jenkins_job": "sample-pipeline",     // Pipeline name (optional)
  "iat": 1234567890,                    // Issued at
  "nbf": 1234567890,                    // Not before
  "exp": 1234568790                     // Expires
}
```### Policy Templating
```hcl
# Dynamic path based on pipeline name
path "kv/data/dev/apps/{{identity.entity.aliases.auth_jwt_5f35b701.metadata.job}}/*" {
  capabilities = ["read"]
}
```

**Result**: `jenkins_job: "sample-pipeline"` → Access to `kv/data/dev/apps/sample-pipeline/*`

### Entity Lifecycle
```
1. First team login      → Entity created with team-based alias
2. Same team member      → Same entity reused, alias metadata updated  
3. Different team login  → New team entity created (if using different team)
4. No churning          → Entity/alias IDs remain stable within teams
```

---

## Manual Setup (for reference)

### 1) Start Containers
```bash
docker compose up -d
```

### 2) Initialize Vault (first time only)
```bash
# Initialize and get unseal keys + root token
docker exec vault vault operator init

# Unseal with 3 of 5 keys
docker exec vault vault operator unseal <key1>
docker exec vault vault operator unseal <key2>
docker exec vault vault operator unseal <key3>
```

### 3) Configure Vault
```bash
export VAULT_ADDR="http://localhost:8200"
export VAULT_TOKEN="<your-root-token-from-vault-keys.txt>"

# Run setup script
cd vault/scripts && ./setup_vault.sh

# Seed test secrets
./seed_secret.sh
```

### 4) Get Jenkins Admin Password
```bash
docker logs jenkins | grep -A 10 "Please use the following password"
```

## Troubleshooting

### Vault Shows "Sealed" After Restart
This is normal! Vault seals itself on restart for security.
```bash
./scripts/unseal-vault.sh
```

### JWT Authentication Failures
```bash
# Check JWT role configuration for teams
export VAULT_ADDR="http://localhost:8200"
export VAULT_TOKEN="<your-root-token-from-vault-keys.txt>"

# Check team roles
vault read auth/jenkins-jwt/role/mobile-developers
vault read auth/jenkins-jwt/role/frontend-developers
vault read auth/jenkins-jwt/role/backend-developers
vault read auth/jenkins-jwt/role/devops-team

# Verify bound claims are set correctly
# Should show: bound_claims = map[selected_group:mobile-developers]
```

### Permission Denied Errors
1. Check policy exists for the team:
   ```bash
   vault policy read mobile-developers
   vault policy read frontend-developers  
   vault policy read backend-developers
   vault policy read devops-team
   ```

2. Verify team-specific secrets exist:
   ```bash
   vault kv get kv/dev/apps/mobile-app/example
   vault kv get kv/dev/apps/frontend-app/example
   vault kv get kv/dev/apps/backend-service/example
   vault kv get kv/dev/apps/devops-tools/example
   ```

### Container Startup Issues
- Check Docker is running
- Ensure ports 8080, 8200, 8201 are available
- Check logs: `docker logs vault` or `docker logs jenkins`

## Project Structure

```
jenkins-vault-poc/
├── README.md                    # This file
├── docker-compose.yml           # Container orchestration
├── vault-keys.txt              # Vault unseal keys (WARNING: Keep secure!)
│
├── data/                       # Persistent data (survives restarts)
│   ├── jenkins_home/           # Jenkins configuration & jobs
│   └── vault/                  # Vault Raft storage & config
│
├── jenkins/                    # Custom Jenkins image
│   └── Dockerfile              # Adds curl, jq for JWT processing
│
├── keys/                       # JWT signing keys
│   ├── jenkins-oidc.key        # Private key (WARNING: Keep secure!)
│   └── jenkins-oidc.pub        # Public key
│
├── scripts/                    # Infrastructure automation
│   ├── start.sh                # Start & unseal everything
│   ├── stop.sh                 # Graceful shutdown
│   └── unseal-vault.sh         # Auto-unseal utility
│
├── vault/                      # Vault configuration
│   ├── config/vault.hcl        # Production Vault config
│   ├── policies/               # Team-based policies
│   │   ├── mobile-developers.hcl
│   │   ├── frontend-developers.hcl
│   │   ├── backend-developers.hcl
│   │   └── devops-team.hcl
│   └── scripts/
│       ├── setup_vault.sh      # Configure JWT auth + team setup
│       ├── demo_role_based_auth.sh  # Team authentication demo
│       └── seed_secret.sh      # Populate team-specific test secrets
│
├── pipelines/                  # Example pipelines
│   └── Jenkinsfile.role-selection  # Team-based role selection example
│
├── okta/                       # Authentication docs
│   └── okta_sso_notes.md       # Okta SSO integration notes
│
└── verification/               # Testing & validation
    ├── verify-no-churn.sh      # Proves no entity churning
    ├── comprehensive-team-demo.sh  # Team-based demo
    └── demo-team-entities.sh    # Basic entity demo
```

## Production Recommendations

### For Team-Based Organizations:

1. **Use team-specific `selected_group` claims**:
   ```json
   {"selected_group": "mobile-developers"}     // Mobile team
   {"selected_group": "frontend-developers"}   // Frontend team  
   {"selected_group": "backend-developers"}    // Backend team
   {"selected_group": "devops-team"}           // DevOps team
   ```

2. **Map Okta groups to teams**:
   - Okta group `mobile-developers` → JWT `selected_group: "mobile-developers"`
   - Results in 1 entity per team (logically groups identical workloads)

3. **Implement proper key rotation**:
   - Rotate JWT signing keys regularly
   - Update Vault JWT auth configuration accordingly

4. **Monitor entity growth**:
   ```bash
   # Check entity count periodically
   vault list identity/entity/id | wc -l
   ```

### Security Best Practices:

- Secure the private key (`keys/jenkins-oidc.key`)
- Secure the Vault root token (`vault-keys.txt`)
- Implement key rotation procedures
- Monitor Vault audit logs
- Use least-privilege policies
- Enable TLS in production

---

## Support & Documentation

- **Vault JWT Auth**: https://developer.hashicorp.com/vault/docs/auth/jwt
- **Jenkins Integration**: See `pipelines/Jenkinsfile.role-selection`
- **Policy Templating**: https://developer.hashicorp.com/vault/docs/concepts/policies#templated-policies
- **Raft Storage**: https://developer.hashicorp.com/vault/docs/configuration/storage/raft
