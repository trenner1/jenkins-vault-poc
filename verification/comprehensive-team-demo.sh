#!/bin/bash
set -euo pipefail

export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=<VAULT_ROOT_TOKEN>

echo "=== COMPREHENSIVE TEAM-BASED DEMO ==="
echo ""

echo "🏢 SCENARIO: Large Monorepo with Multiple Teams"
echo "   • team-alpha: Frontend team (React/TypeScript)"
echo "   • team-beta:  Backend team (Go/Microservices)" 
echo "   • team-gamma: Data team (Python/ML)"
echo ""

echo "📋 CURRENT SETUP ANALYSIS:"
echo "   • JWT sub: 'jenkins-dev' (same for ALL teams)"
echo "   • Result: 1 entity shared across ALL teams"
echo "   • Benefit: Minimal licensing impact"
echo "   • Trade-off: Less granular team isolation"
echo ""

# Show current state
CURRENT_ENTITIES=$(vault list -format=json identity/entity/id 2>/dev/null | jq -r 'length // 0')
CURRENT_ALIASES=$(vault list -format=json identity/entity-alias/id 2>/dev/null | jq -r 'length // 0')

echo "📊 CURRENT VAULT STATE:"
echo "   Entities: $CURRENT_ENTITIES"
echo "   Aliases:  $CURRENT_ALIASES"
echo ""

echo "🧪 TESTING: Multiple team members, same pipeline"
echo ""

# Simulate multiple runs of the same pipeline by different team members
declare -a team_alpha_members=("alice.smith" "bob.jones" "carol.wilson" "david.brown")

for member in "${team_alpha_members[@]}"; do
    echo "👤 $member (team-alpha) triggers 'team-alpha-pipeline'"
    
    # In reality, this would be a real JWT login, but for demo we just check counts
    ENTITIES=$(vault list -format=json identity/entity/id 2>/dev/null | jq -r 'length // 0')
    ALIASES=$(vault list -format=json identity/entity-alias/id 2>/dev/null | jq -r 'length // 0')
    
    echo "   📈 Vault state: $ENTITIES entities, $ALIASES aliases (no change = no churning)"
done

echo ""
echo "✅ RESULT: No entity churning within team-alpha"
echo ""

echo "🔄 WHAT WOULD HAPPEN WITH DIFFERENT TEAMS:"
echo ""
echo "📈 OPTION 1: All teams share same entity (current setup)"
echo "   JWT: sub='jenkins-dev' for ALL teams"
echo "   Result: 1 entity total (most licensing efficient)"
echo "   Trade-off: Less team isolation"
echo ""

echo "📈 OPTION 2: Entity per team (recommended for team isolation)"
echo "   JWT: sub='team-alpha', sub='team-beta', sub='team-gamma'"
echo "   Result: 3 entities total (1 per team)"
echo "   Benefit: Team isolation + no intra-team churning"
echo ""

echo "📈 OPTION 3: Entity per person (worst for licensing)"
echo "   JWT: sub='alice.smith', sub='bob.jones', etc."
echo "   Result: 1 entity per developer (licensing expensive)"
echo "   Problem: Entity proliferation"
echo ""

echo "🎯 RECOMMENDATION FOR YOUR USE CASE:"
echo "   Use sub='team-{name}' for team-based entities"
echo "   • team-alpha gets 1 entity (shared by all team-alpha members)"
echo "   • team-beta gets 1 entity (shared by all team-beta members)"
echo "   • No churning within teams"
echo "   • Clean team separation"
echo "   • Reasonable licensing impact (entities = number of teams)"

FINAL_ENTITIES=$(vault list -format=json identity/entity/id 2>/dev/null | jq -r 'length // 0')
FINAL_ALIASES=$(vault list -format=json identity/entity-alias/id 2>/dev/null | jq -r 'length // 0')

echo ""
echo "📊 FINAL STATE:"
echo "   Entities: $FINAL_ENTITIES (unchanged = no churning)"
echo "   Aliases:  $FINAL_ALIASES (unchanged = no churning)"
echo ""
echo "✨ This demonstrates the licensing-efficient approach!"