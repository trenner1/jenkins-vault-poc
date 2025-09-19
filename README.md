# Jenkins ↔ Vault JWT Authentication POC

A production-ready proof of concept demonstrating **team-based JWT authentication** between Jenkins and HashiCorp Vault with **licensing-efficient entity management**.

## What This POC Proves

- **Zero Entity Churning**: Same entity/alias reused across team member logins  
- **Licensing Efficient**: Entity count scales with teams, not developers  
- **Production Ready**: Raft storage, proper policies, automation, persistence  
- **Secure**: Job-scoped access with dynamic policy templating  
- **Scalable**: Supports large monorepos with multiple development teams  

**Verified**: Real JWT authentication tested with entity ID tracking - **no churning detected**.

## Key Features

- **JWT Authentication**: Jenkins → Vault using self-signed JWTs
- **Team-Based Access**: One entity per team (not per developer) for licensing efficiency
- **No Entity Churning**: Proven entity/alias reuse within teams
- **Job-Scoped Secrets**: Dynamic policy templating based on pipeline context
- **Persistent Data**: Survives container restarts with auto-unseal
- **Production Ready**: Raft storage, proper policies, automation scripts

## Architecture Overview

### Team-Based Entity Model
```
Team Alpha (Frontend)     →  Entity: jenkins-dev  →  Secrets: kv/dev/apps/team-alpha-pipeline/*
├── alice.smith          
├── bob.jones            
└── carol.wilson         

Team Beta (Backend)      →  Entity: jenkins-dev  →  Secrets: kv/dev/apps/team-beta-pipeline/*
├── dave.brown           
├── eve.taylor           
└── frank.moore          
```

**Benefits:**
- **No Churning**: Same entity reused by all team members
- **Licensing Efficient**: Entity count = number of teams (not developers)
- **Secure**: Job-scoped access via policy templating
- **Scalable**: Supports large organizations with multiple teams

## Comparison with Other Approaches

| Approach | Entities Created | Licensing Impact | Team Isolation | Complexity |
|----------|------------------|------------------|----------------|------------|
| **Per Developer** | 1 per developer | High | Excellent | Medium |
| **Single Shared** | 1 total | Minimal | None | Low |
| **Per Team (This POC)** | 1 per team | Low | Good | Medium |

### Why Team-Based is Optimal:
- **Licensing**: Pay for teams, not individual developers
- **Security**: Natural isolation boundaries align with org structure  
- **Scalability**: Linear growth (teams) vs exponential (developers)
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
- **Policy**: `jenkins-dev` (job-scoped access)
- **Role**: `dev-builds` (for Jenkins pipelines)
- **Secrets**: Seeded test data in `kv/dev/apps/`

## Verification & Testing

### Verify No Entity Churning
```bash
# Run comprehensive verification test
./verification/verify-no-churn.sh
```

This script:
1. Records current entity/alias state
2. Performs real JWT authentication
3. Verifies same entity/alias IDs are reused
4. **Proves no churning occurs**

### Demo Team-Based Access
```bash
# Show team-based entity management concepts
./verification/comprehensive-team-demo.sh
```

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
  "sub": "jenkins-dev",                 // Team identifier (shared)
  "aud": "vault",                       // Vault audience
  "env": "dev",                         // Environment
  "jenkins_job": "sample-pipeline",     // Pipeline name (mapped to 'job')
  "build_id": "123",                    // Build number
  "user": "alice.smith",                // Individual developer
  "iat": 1234567890,                    // Issued at
  "exp": 1234568790                     // Expires
}
```

### Policy Templating
```hcl
# Dynamic path based on pipeline name
path "kv/data/dev/apps/{{identity.entity.aliases.auth_jwt_5f35b701.metadata.job}}/*" {
  capabilities = ["read"]
}
```

**Result**: `jenkins_job: "sample-pipeline"` → Access to `kv/data/dev/apps/sample-pipeline/*`

### Entity Lifecycle
```
1. First JWT login   → Entity created with alias
2. Same team login   → Same entity reused, alias metadata updated  
3. Different team    → New entity created (if using different 'sub')
4. No churning      → Entity/alias IDs remain stable
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
# Check JWT role configuration
export VAULT_ADDR="http://localhost:8200"
export VAULT_TOKEN="<your-root-token-from-vault-keys.txt>"
vault read auth/jenkins-jwt/role/dev-builds

# Verify claim mappings are set
# Should show: claim_mappings = map[jenkins_job:job]
```

### Permission Denied Errors
1. Check policy has correct accessor ID:
   ```bash
   vault auth list  # Get current accessor
   vault policy read jenkins-dev  # Verify policy uses correct accessor
   ```

2. Verify secret exists:
   ```bash
   vault kv get kv/dev/apps/sample-pipeline/example
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
│   ├── policies/jenkins-dev.hcl # JWT-based access policy
│   └── scripts/
│       ├── setup_vault.sh      # Configure JWT auth
│       └── seed_secret.sh      # Populate test secrets
│
├── pipelines/                  # Example pipelines
│   └── Jenkinsfile.demo        # Full JWT → Vault integration
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

1. **Use team-specific `sub` claims**:
   ```json
   {"sub": "team-alpha"}  // Frontend team
   {"sub": "team-beta"}   // Backend team  
   {"sub": "team-gamma"}  // Data team
   ```

2. **Map Okta groups to teams**:
   - Okta group `team-alpha` → JWT `sub: "team-alpha"`
   - Results in 1 entity per team (licensing efficient)

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
- **Jenkins Integration**: See `pipelines/Jenkinsfile.demo`
- **Policy Templating**: https://developer.hashicorp.com/vault/docs/concepts/policies#templated-policies
- **Raft Storage**: https://developer.hashicorp.com/vault/docs/configuration/storage/raft
