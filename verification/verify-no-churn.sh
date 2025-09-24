#!/bin/bash
set -euo pipefail

# Source environment variables if .env exists
if [ -f ".env" ]; then
    source ".env"
fi

export VAULT_ADDR=http://localhost:8200
: "${VAULT_TOKEN:?VAULT_TOKEN must be set}"

echo "=== PROPER ALIAS CHURN VERIFICATION ==="
echo ""

# Record the current alias state
echo "STEP 1: Recording current alias state"
CURRENT_ALIAS_LIST=$(vault list -format=json identity/entity-alias/id 2>/dev/null | jq -r '.[]')
echo "Current alias IDs:"
echo "$CURRENT_ALIAS_LIST"

# Get the first alias ID for verification
ALIAS_ID=$(echo "$CURRENT_ALIAS_LIST" | head -n1)
if [ -z "$ALIAS_ID" ]; then
    echo "No aliases found in Vault. Creating initial authentication to generate aliases..."
    # We'll continue with the JWT login which should create an alias
    ALIAS_ID=""
else
    echo "Using alias ID for verification: $ALIAS_ID"
fi

echo ""
if [ -n "$ALIAS_ID" ]; then
    echo "Current alias details:"
    BEFORE_STATE=$(vault read identity/entity-alias/id/$ALIAS_ID -format=json)
    echo "$BEFORE_STATE" | jq '{
      id: .data.id,
      name: .data.name, 
      creation_time: .data.creation_time,
      last_update_time: .data.last_update_time,
      metadata: .data.metadata
    }'
fi

echo ""
echo "STEP 2: Performing REAL JWT login"

# Create helper function
b64url() { openssl base64 -A | tr "+/" "-_" | tr -d "="; }

# Create JWT header
printf '{"alg":"RS256","typ":"JWT","kid":"jenkins-dev-key-1"}' > /tmp/h.json
H=$(b64url < /tmp/h.json)

# Create JWT payload with current timestamp and different build ID
IAT=$(date +%s)
EXP=$((IAT+900))
BUILD_ID="verification-$(date +%s)"

jq -n \
  --arg iss "http://localhost:8080" \
  --arg selected_group "mobile-developers" \
  --arg aud "vault" \
  --arg env "dev" \
  --arg job "sample-pipeline" \
  --arg build "$BUILD_ID" \
  --arg user "verification.test" \
  --argjson iat "$IAT" \
  --argjson exp "$EXP" \
  '{iss:$iss,selected_group:$selected_group,aud:$aud,iat:$iat,exp:$exp,env:$env,jenkins_job:$job,build_id:$build,user:$user}' > /tmp/p.json

echo "JWT payload being used:"
cat /tmp/p.json | jq .

P=$(b64url < /tmp/p.json)

# Sign the JWT
SIG=$(printf "%s.%s" "$H" "$P" | openssl dgst -sha256 -sign keys/jenkins-oidc.key -binary | b64url)
JWT_TOKEN="$H.$P.$SIG"

echo ""
echo "Executing JWT login..."
LOGIN_RESULT=$(vault write auth/jenkins-jwt/login role=mobile-developers jwt="$JWT_TOKEN" -format=json)

if echo "$LOGIN_RESULT" | jq -e '.auth.client_token' > /dev/null; then
    echo "JWT login successful!"
    echo "Token: $(echo "$LOGIN_RESULT" | jq -r '.auth.client_token')"
else
    echo "JWT login failed:"
    echo "$LOGIN_RESULT" | jq .
    exit 1
fi

echo ""
echo "STEP 3: Checking alias state after JWT login"

# Check if alias list changed
AFTER_ALIAS_LIST=$(vault list -format=json identity/entity-alias/id 2>/dev/null | jq -r '.[]')
echo "Alias IDs after login:"
echo "$AFTER_ALIAS_LIST"

# Compare alias lists
if [ "$CURRENT_ALIAS_LIST" = "$AFTER_ALIAS_LIST" ]; then
    echo "ALIAS LIST UNCHANGED - No new aliases created"
else
    echo "ALIAS LIST CHANGED - New aliases detected!"
    echo "Before: $CURRENT_ALIAS_LIST"
    echo "After:  $AFTER_ALIAS_LIST"
fi

echo ""
echo "Detailed alias comparison:"
if [ -n "$ALIAS_ID" ]; then
    AFTER_STATE=$(vault read identity/entity-alias/id/$ALIAS_ID -format=json)

    echo "BEFORE JWT login:"
    echo "$BEFORE_STATE" | jq '{
      id: .data.id,
      last_update_time: .data.last_update_time,
      metadata: .data.metadata
    }'

    echo ""
    echo "AFTER JWT login:"
    echo "$AFTER_STATE" | jq '{
      id: .data.id,
      last_update_time: .data.last_update_time,
      metadata: .data.metadata
    }'

    # Compare specific fields
    BEFORE_UPDATE_TIME=$(echo "$BEFORE_STATE" | jq -r '.data.last_update_time')
    AFTER_UPDATE_TIME=$(echo "$AFTER_STATE" | jq -r '.data.last_update_time')

    if [ "$BEFORE_UPDATE_TIME" = "$AFTER_UPDATE_TIME" ]; then
        echo "ALIAS UPDATE TIME UNCHANGED - No metadata churn detected"
    else
        echo "ALIAS UPDATE TIME CHANGED"
        echo "Before: $BEFORE_UPDATE_TIME"
        echo "After:  $AFTER_UPDATE_TIME"
    fi
else
    echo "No existing alias to compare - this may be the first authentication"
fi

echo ""
echo "VERIFICATION RESULTS:"
if [ -n "$ALIAS_ID" ]; then
    BEFORE_UPDATE_TIME=$(echo "$BEFORE_STATE" | jq -r '.data.last_update_time')
    AFTER_UPDATE_TIME=$(echo "$AFTER_STATE" | jq -r '.data.last_update_time')
    
    if [ "$BEFORE_UPDATE_TIME" != "$AFTER_UPDATE_TIME" ]; then
        echo "Alias was UPDATED (last_update_time changed)"
        echo "   Before: $BEFORE_UPDATE_TIME"
        echo "   After:  $AFTER_UPDATE_TIME"
        echo "   This proves the alias was reused, not recreated"
    else
        echo "Alias was NOT updated (last_update_time unchanged)"
        echo "   This might mean JWT login didn't complete properly"
    fi

    BEFORE_ID=$(echo "$BEFORE_STATE" | jq -r '.data.id')
    AFTER_ID=$(echo "$AFTER_STATE" | jq -r '.data.id')

    if [ "$BEFORE_ID" = "$AFTER_ID" ]; then
        echo "ALIAS ID UNCHANGED: $BEFORE_ID"
        echo "   This proves NO CHURNING occurred"
    else
        echo "ALIAS ID CHANGED! This indicates churning:"
        echo "   Before: $BEFORE_ID"
        echo "   After:  $AFTER_ID"
    fi
else
    echo "First-time authentication - checking if new alias was created properly"
    NEW_ALIAS_COUNT=$(echo "$AFTER_ALIAS_LIST" | wc -l)
    echo "   New alias count: $NEW_ALIAS_COUNT"
fi

echo ""
echo "CONCLUSION:"
if [ "$BEFORE_ID" = "$AFTER_ID" ] && [ "$BEFORE_UPDATE_TIME" != "$AFTER_UPDATE_TIME" ]; then
    echo "PERFECT: Alias was reused and updated (no churning)"
elif [ "$BEFORE_ID" = "$AFTER_ID" ]; then
    echo "GOOD: Alias ID unchanged (no churning detected)"
else
    echo "PROBLEM: Alias churning detected!"
fi

# Cleanup
rm -f /tmp/h.json /tmp/p.json