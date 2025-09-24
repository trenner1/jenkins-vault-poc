# Okta-Jenkins-Vault Integration Guide

## Current Setup
- **Okta OIDC App**: Configured for Jenkins SSO
- **Scopes**: `openid email profile groups` 
- **Redirect URI**: `http://localhost:8080/securityRealm/finishLogin`

## Jenkins Configuration for Group Claims

### 1. Jenkins OIDC Plugin Configuration
Ensure Jenkins OIDC plugin is configured to:
- Extract groups from Okta token
- Make groups available as environment variables
- Pass groups to build context

### 2. Okta Group Mapping
Create these groups in Okta and assign users:

| Okta Group Name | Maps to Vault Role | Purpose |
|----------------|-------------------|---------|
| `mobile-developers` | `mobile-developers` | Mobile app team |
| `frontend-developers` | `frontend-developers` | Frontend team |
| `backend-developers` | `backend-developers` | Backend team |
| `devops-team` | `devops-team` | DevOps/Admin team |

### 3. Pipeline Integration
The updated pipeline now:
- Extracts Okta groups from Jenkins context
- Validates user's group membership
- Only allows JWT creation for authorized teams
- Includes group claims in JWT and token metadata

## Production Implementation Steps

### Step 1: Update Jenkins OIDC Configuration
```groovy
// In Jenkins Global Security Configuration
oic {
    clientId = 'your-okta-client-id'
    clientSecret = 'your-okta-client-secret' 
    tokenServerUrl = 'https://your-org.okta.com/oauth2/default/v1/token'
    authorizationServerUrl = 'https://your-org.okta.com/oauth2/default/v1/authorize'
    userInfoServerUrl = 'https://your-org.okta.com/oauth2/default/v1/userinfo'
    userNameField = 'email'
    scopes = 'openid email profile groups'
    groupsFieldName = 'groups'  // Important for group extraction
}
```

### Step 2: Create Okta Groups
In Okta Admin Console:
1. Navigate to Directory → Groups
2. Create groups following naming convention
3. Assign users to appropriate groups
4. Ensure groups are included in OIDC token claims

### Step 3: Update Pipeline Environment Variables
The pipeline expects these environment variables:
- `OKTA_GROUPS`: Space-separated list of user's Okta groups
- `BUILD_USER_ID`: User's email from Okta

### Step 4: Vault Policy Binding (Optional Enhancement)
Consider updating Vault JWT roles to validate groups:
```hcl
# Example: mobile-developers JWT role
path "auth/jenkins-jwt/role/mobile-developers" {
  bound_claims = {
    "okta_groups" = "*mobile-developers*"
  }
}
```

## Security Benefits
**Group-based authorization** instead of user-specific mappings
**Centralized identity management** through Okta
**Automatic group updates** when users change teams
**Audit trail** of group memberships in token metadata
**Scalable** for large organizations

## Testing the Integration
1. User logs into Jenkins via Okta SSO
2. Pipeline extracts user's Okta groups
3. Validates selected role against group membership
4. Creates JWT with group claims
5. Vault validates and grants appropriate access

## Fallback Strategy
Current implementation includes fallback mapping for demo/testing when Okta groups aren't available.
Remove the fallback section in production once Okta integration is fully configured.