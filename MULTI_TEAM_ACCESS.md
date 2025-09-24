# Multi-Team Access Scenarios

## The Challenge

When users work across multiple teams or need temporary access to different team resources, they need different Vault access levels for different contexts:

- **Sarah** is normally on the QA team but is temporarily helping the backend-developers team with deployment issues
- **Mike** is a devops-team member but when doing code reviews with frontend-developers he needs their specific secrets
- **Alex** works on both mobile-developers (iOS/Android apps) and backend-developers (API services) projects

## Solution: Team-Based Role Selection

Instead of mapping users to fixed roles, let users **choose the appropriate team context for each pipeline run** based on the work they're doing.

### Benefits of Team Selection

1. **Team Isolation**: Each team gets their own entity and policies, maintaining clear boundaries
2. **Multi-Team Flexibility**: Same user can work with different team access levels for different projects  
3. **Temporary Access**: No need to modify user groups for short-term cross-team assignments
4. **Audit Clarity**: Each pipeline run logs exactly what team context was requested and why
5. **No Entity Churn**: Users working within the same team always get the same entity

### Example Scenarios

#### Scenario 1: QA Engineer Helping with Backend Development
```
User: Sarah (normally QA team)
Task: Emergency API hotfix
Selection: 
  - Team: "backend-developers" (needs backend secrets)
  - Project: "user-api" 
  - Environment: "prod"
```

#### Scenario 2: DevOps Engineer Doing Frontend Code Review  
```
User: Mike (devops-team member)
Task: Reviewing frontend developer's CI pipeline
Selection:
  - Team: "frontend-developers" (needs frontend build secrets)
  - Project: "web-app"
  - Environment: "dev"
```

#### Scenario 3: Cross-Functional Developer
```
User: Alex (works on multiple teams)
Morning Task: Mobile app feature development
  - Team: "mobile-developers"
  - Project: "ios-app"
  
Afternoon Task: Infrastructure update
  - Team: "devops-team" 
  - Project: "kubernetes-cluster"
```

## Implementation Pattern

### 1. Jenkins Pipeline Parameters
```groovy
parameters {
    choice(
        name: 'SELECTED_TEAM',
        choices: ['mobile-developers', 'frontend-developers', 'backend-developers', 'devops-team'],
        description: '''Choose team context for this specific task:
        - mobile-developers: iOS/Android app development and deployment
        - frontend-developers: Web frontend development and build secrets
        - backend-developers: API services, databases, backend infrastructure  
        - devops-team: Infrastructure, CI/CD, monitoring and platform tools'''
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
  "selected_group": "backend-developers",  // ← User's team choice for this run
  "jenkins_job": "user-api",              // ← Project context
  "sub": "sarah@company.com",             // ← User identity for audit
  "iss": "http://localhost:8080",
  "aud": "vault",
  "env": "dev",
  "build_id": "build-123",
  "user": "sarah.smith"
}
```

### 3. Audit Trail
Every pipeline run logs:
- Who requested access (`sub` and `user` claims)
- What team context they chose (`selected_group` claim)  
- For which project (`jenkins_job` claim)
- When it happened (timestamp)
- What job triggered it (Jenkins job name)
- Specific build information (`build_id` claim)

## Security Considerations

### User Education
- Train users to select appropriate teams: "Choose the team context that matches your current task"
- Provide clear descriptions of what each team context provides access to
- Show examples of when to use each team context

### Monitoring & Alerts
- Alert on unusual patterns (mobile developer suddenly using devops-team context frequently)
- Monitor cross-team access (user accessing team contexts outside their normal scope)
- Track team context switching (user choosing different teams than their primary assignment)

### Guardrails
- Consider environment-based restrictions (only certain users can use "devops-team" context for "prod")
- Implement approval workflows for sensitive team/environment combinations
- Time-bound access for temporary cross-team assignments

## Alternative: Hybrid Approach

For organizations wanting some automation with user override:

1. **Auto-suggest** team based on user's primary team membership
2. **Allow override** for multi-team scenarios  
3. **Require justification** for cross-team access

```groovy
// Auto-detect user's primary team from Okta groups or user attributes
def suggestedTeam = getUserPrimaryTeam(currentUser)

// But allow override with justification
parameters {
    choice(
        name: 'SELECTED_TEAM',
        choices: [suggestedTeam, 'mobile-developers', 'frontend-developers', 'backend-developers', 'devops-team'],
        description: "Suggested: ${suggestedTeam} (based on your primary team assignment)"
    )
    text(
        name: 'CROSS_TEAM_JUSTIFICATION',
        description: 'If using different team context than suggested, explain why'
    )
}
```

## Team-Based Entity Management

### Entity Strategy
- **One entity per team**: `mobile-developers`, `frontend-developers`, `backend-developers`, `devops-team`
- **Stable entities**: Users consistently working within a team context get the same entity
- **No churning**: Team-based approach prevents entity proliferation while maintaining isolation
- **Cross-team work**: Same user can access different team entities for different projects

### Licensing Benefits
- **Predictable licensing**: 4 entities total (1 per team) regardless of user count
- **Team isolation**: Each team gets separate policies and secret access
- **Scalable**: Adding users to existing teams doesn't create new entities

This approach handles multi-team scenarios perfectly: **users can work across teams with appropriate access levels while maintaining security, audit trails, and licensing efficiency**.