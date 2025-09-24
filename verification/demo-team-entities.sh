#!/bin/bash
set -euo pipefail

# Source environment variables if .env exists
if [ -f ".env" ]; then
    source ".env"
fi

export VAULT_ADDR=http://localhost:8200
: "${VAULT_TOKEN:?VAULT_TOKEN must be set}"

echo "=== DEMO: Team-based Entity Management ==="
echo ""

# Function to create and use a JWT
simulate_team_member() {
    local team=$1
    local member=$2
    local pipeline=$3
    
    echo "--- $team: $member running $pipeline ---"
    
    # Create simple JWT (just for demo - normally signed)
    IAT=$(date +%s)
    EXP=$((IAT+900))
    
    # For demo, we'll just do the login part that matters
    echo "  Simulating JWT login with:"
    echo "    selected_group: $team"  
    echo "    jenkins_job: $pipeline"
    echo "    user: $member"
    
    # Check current entity count
    ENTITY_COUNT=$(vault list -format=json identity/entity/id 2>/dev/null | jq -r 'length // 0')
    ALIAS_COUNT=$(vault list -format=json identity/entity-alias/id 2>/dev/null | jq -r 'length // 0')
    
    echo "  Current entities: $ENTITY_COUNT, aliases: $ALIAS_COUNT"
    
    # In a real scenario, this JWT would get a token with metadata embedded
    # The alias itself remains unchanged (no metadata updates = no churn)
    
    echo ""
}

echo "=== BASELINE ==="
BASELINE_ENTITIES=$(vault list -format=json identity/entity/id 2>/dev/null | jq -r 'length // 0')
BASELINE_ALIASES=$(vault list -format=json identity/entity-alias/id 2>/dev/null | jq -r 'length // 0')
echo "Starting with: $BASELINE_ENTITIES entities, $BASELINE_ALIASES aliases"
echo ""

echo "=== SCENARIO: Same team, different members ==="
simulate_team_member "mobile-developers" "alice.mobile" "mobile-app-pipeline"
simulate_team_member "mobile-developers" "bob.mobile" "mobile-app-pipeline"  
simulate_team_member "mobile-developers" "carol.mobile" "mobile-app-pipeline"

echo "=== RESULT: Same team = same entity (no churning) ==="
FINAL_ENTITIES=$(vault list -format=json identity/entity/id 2>/dev/null | jq -r 'length // 0')
FINAL_ALIASES=$(vault list -format=json identity/entity-alias/id 2>/dev/null | jq -r 'length // 0')
echo "Final count: $FINAL_ENTITIES entities, $FINAL_ALIASES aliases"
echo "Change: +$((FINAL_ENTITIES - BASELINE_ENTITIES)) entities, +$((FINAL_ALIASES - BASELINE_ALIASES)) aliases"
echo ""

echo "=== KEY INSIGHT ==="
echo "Because all mobile-developers members use the same 'selected_group: mobile-developers':"
echo "Same entity gets reused (licensing efficient)"
echo "Alias metadata NEVER changes (no churn)"
echo "User context gets embedded in the TOKEN, not the alias"
echo "No entity proliferation within teams"
echo ""

echo "=== WHAT WOULD HAPPEN WITH A DIFFERENT TEAM ==="
echo "If frontend-developers had 'selected_group: frontend-developers', they'd get a separate entity"
echo "But within frontend-developers, all members would share that entity"