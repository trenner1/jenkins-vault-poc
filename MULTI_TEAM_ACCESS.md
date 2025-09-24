# Multi-Team Access Scenarios

## The Challenge

When users are temporarily added to multiple teams or work across projects, they need different Vault access levels for different contexts:

- **Sarah** is normally a QA engineer (readonly access) but is temporarily helping with backend deployment (needs admin access)
- **Mike** is a platform admin but when doing code reviews he only needs developer access  
- **Alex** works on both frontend (developer access) and infrastructure (admin access) projects

## Solution: Context-Aware Role Selection

Instead of mapping users to fixed roles, let users **choose the appropriate role for each pipeline run** based on the work they're doing.

### Benefits of User Choice

1. **Principle of Least Privilege**: Users can select the minimum access needed for each task
2. **Multi-Team Flexibility**: Same user can work with different access levels for different projects
3. **Temporary Access**: No need to modify user groups for short-term assignments
4. **Audit Clarity**: Each pipeline run logs exactly what access was requested and why
5. **No Entity Churn**: Same user working on different projects gets the same entity, just different policies

### Example Scenarios

#### Scenario 1: QA Engineer Helping with Deployment
```
User: Sarah (normally QA team)
Task: Emergency deployment fix
Selection: 
  - Role: "admin" (needs deployment secrets)
  - Project: "backend-api" 
  - Environment: "prod"
```

#### Scenario 2: Platform Admin Doing Code Review  
```
User: Mike (platform admin)
Task: Reviewing developer's database migration
Selection:
  - Role: "developer" (principle of least privilege)
  - Project: "user-service"
  - Environment: "dev"
```

#### Scenario 3: Cross-Functional Developer
```
User: Alex (works on multiple teams)
Morning Task: Frontend feature development
  - Role: "developer"
  - Project: "web-app"
  
Afternoon Task: Infrastructure update
  - Role: "admin" 
  - Project: "kubernetes-cluster"
```

## Implementation Pattern

### 1. Jenkins Pipeline Parameters
```groovy
parameters {
    choice(
        name: 'VAULT_ROLE',
        choices: ['readonly', 'developer', 'admin'],
        description: '''Choose access level for this specific task:
        • readonly - For testing, monitoring, code review
        • developer - For feature development, CI builds  
        • admin - For deployments, infrastructure changes'''
    )
    string(
        name: 'PROJECT_CONTEXT', 
        defaultValue: "${env.JOB_NAME}",
        description: 'Project/team context (allows cross-team work)'
    )
}
```

### 2. JWT Claims Structure
```json
{
  "role": "developer",           // ← User's choice for this run
  "jenkins_job": "backend-api",  // ← Project context (may differ from job name)
  "sub": "sarah@company.com",    // ← User identity for audit
  "iss": "http://localhost:8080",
  "aud": "vault",
  "env": "dev"
}
```

### 3. Audit Trail
Every pipeline run logs:
- Who requested access (`sub` claim)
- What role they chose (`role` claim)  
- For which project (`jenkins_job` claim)
- When it happened (timestamp)
- What job triggered it (Jenkins job name)

## Security Considerations

### User Education
- Train users to select appropriate roles: "Use the minimum access needed for your current task"
- Provide clear descriptions of what each role can do
- Show examples of when to use each role

### Monitoring & Alerts
- Alert on unusual patterns (QA user suddenly using admin role frequently)
- Monitor cross-project access (user accessing projects outside their normal scope)
- Track role escalation (user choosing higher privileges than normal)

### Guardrails
- Consider environment-based restrictions (only certain users can choose "admin" for "prod")
- Implement approval workflows for sensitive combinations
- Time-bound access for temporary assignments

## Alternative: Hybrid Approach

For organizations wanting some automation with user override:

1. **Auto-suggest** role based on user's primary team
2. **Allow override** for multi-team scenarios  
3. **Require justification** for role escalation

```groovy
// Auto-detect user's primary role from Okta groups
def suggestedRole = getUserPrimaryRole(currentUser)

// But allow override with justification
parameters {
    choice(
        name: 'VAULT_ROLE',
        choices: [suggestedRole, 'readonly', 'developer', 'admin'],
        description: "Suggested: ${suggestedRole} (based on your primary team)"
    )
    text(
        name: 'ACCESS_JUSTIFICATION',
        description: 'If using different role than suggested, explain why'
    )
}
```

This approach handles your concern perfectly: **users can work across teams with appropriate access levels while maintaining security and audit trails**.