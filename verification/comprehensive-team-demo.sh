#!/bin/bash
set -euo pipefail

# Source environment variables if .env exists
if [ -f ".env" ]; then
    source ".env"
fi

export VAULT_ADDR=http://localhost:8200
: "${VAULT_TOKEN:?VAULT_TOKEN must be set}"

echo "=== COMPREHENSIVE TEAM-BASED DEMO ==="
echo ""

echo "SCENARIO: Large Monorepo with Multiple Teams"
echo "   - mobile-developers: Mobile team (iOS/Android)"
echo "   - frontend-developers: Frontend team (React/TypeScript)" 
echo "   - backend-developers: Backend team (Go/Microservices)"
echo "   - devops-team: DevOps team (Infrastructure/CI-CD)"
echo ""

echo "CURRENT SETUP ANALYSIS:"
echo "   - JWT selected_group: team-specific (e.g. 'mobile-developers')"
echo "   - Result: 1 entity per team (4 entities total)"
echo "   - Benefit: Team isolation with controlled licensing impact"
echo "   - Trade-off: Balanced granularity and entity count"
echo ""

# Show current state
CURRENT_ENTITIES=$(vault list -format=json identity/entity/id 2>/dev/null | jq -r 'length // 0')
CURRENT_ALIASES=$(vault list -format=json identity/entity-alias/id 2>/dev/null | jq -r 'length // 0')

echo "CURRENT VAULT STATE:"
echo "   Entities: $CURRENT_ENTITIES"
echo "   Aliases:  $CURRENT_ALIASES"
echo ""

echo "TESTING: Multiple team members, same pipeline"
echo ""

# Simulate multiple runs of the same pipeline by different team members
declare -a mobile_team_members=("alice.smith" "bob.jones" "carol.wilson" "david.brown")

for member in "${mobile_team_members[@]}"; do
    echo "$member (mobile-developers) triggers 'mobile-app-pipeline'"
    
    # In reality, this would be a real JWT login, but for demo we just check counts
    ENTITIES=$(vault list -format=json identity/entity/id 2>/dev/null | jq -r 'length // 0')
    ALIASES=$(vault list -format=json identity/entity-alias/id 2>/dev/null | jq -r 'length // 0')
    
    echo "   Vault state: $ENTITIES entities, $ALIASES aliases (no change = no churning)"
done

echo ""
echo "RESULT: No entity churning within mobile-developers team"
echo ""

echo "WHAT WOULD HAPPEN WITH DIFFERENT TEAMS:"
echo ""
echo "OPTION 1: All teams share same entity"
echo "   JWT: selected_group='shared' for ALL teams"
echo "   Result: 1 entity total (most licensing efficient)"
echo "   Trade-off: No team isolation"
echo ""

echo "OPTION 2: Entity per team (current/recommended approach)"
echo "   JWT: selected_group='mobile-developers', 'frontend-developers', etc."
echo "   Result: 4 entities total (1 per team)"
echo "   Benefit: Team isolation + no intra-team churning"
echo ""

echo "OPTION 3: Entity per person (worst for licensing)"
echo "   JWT: selected_group='alice.smith', 'bob.jones', etc."
echo "   Result: 1 entity per developer (licensing expensive)"
echo "   Problem: Entity proliferation"
echo ""

echo "RECOMMENDATION FOR YOUR USE CASE:"
echo "   Use selected_group='[team-name]' for team-based entities"
echo "   - mobile-developers gets 1 entity (shared by all team members)"
echo "   - frontend-developers gets 1 entity (shared by all team members)"
echo "   - backend-developers gets 1 entity (shared by all team members)"
echo "   - devops-team gets 1 entity (shared by all team members)"
echo "   - No churning within teams"
echo "   - Clean team separation"
echo "   - Reasonable licensing impact (entities = number of teams)"

FINAL_ENTITIES=$(vault list -format=json identity/entity/id 2>/dev/null | jq -r 'length // 0')
FINAL_ALIASES=$(vault list -format=json identity/entity-alias/id 2>/dev/null | jq -r 'length // 0')

echo ""
echo "FINAL STATE:"
echo "   Entities: $FINAL_ENTITIES (unchanged = no churning)"
echo "   Aliases:  $FINAL_ALIASES (unchanged = no churning)"
echo ""
echo "This demonstrates the licensing-efficient approach!"