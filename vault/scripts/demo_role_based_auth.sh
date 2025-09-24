#!/usr/bin/env bash
# Demo: sign JWTs for each team and login to Vault (Bash 3 compatible + debug)

set -euo pipefail

# Source environment variables if .env exists
if [ -f "../../.env" ]; then
    source "../../.env"
fi

# ---------- CONFIG (override via env) ----------
VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
PRIVKEY="${PRIVKEY:-../../keys/jenkins-oidc.key}"      # <-- point to the SAME key Jenkins uses
KID="${KID:-jenkins-dev-key-1}"                    # <-- must match Vault's JWKS/pubkey entry
ISS="${ISS:-http://localhost:8080}"                # <-- bound_issuer on the auth method / role
AUD="${AUD:-vault}"                                # <-- role's bound_audiences contains this
ENV_CLAIM="${ENV_CLAIM:-dev}"
AUTH_PATH="${AUTH_PATH:-auth/jenkins-jwt}"         # your JWT auth mount path
DEBUG="${DEBUG:-0}"                                # set to 1 for set -x and extra prints
TEAMS=("mobile-developers" "frontend-developers" "backend-developers" "devops-team")
# -----------------------------------------------

# Check for required environment
: "${VAULT_TOKEN:?VAULT_TOKEN must be set (source .env file)}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1"; exit 1; }; }
need openssl; need jq; need curl
need openssl; need jq; need curl

if [ "$DEBUG" = "1" ]; then set -x; fi

if [ ! -f "$PRIVKEY" ]; then
  echo "Private key not found: $PRIVKEY"
  echo "   Fix: export PRIVKEY=/absolute/path/to/jenkins-oidc.key"
  exit 1
fi

echo "=== JWT Team-based Authentication Demo ==="
echo "VAULT_ADDR=$VAULT_ADDR"
echo "PRIVKEY=$PRIVKEY"
echo "KID=$KID"
echo

# Show public key fingerprint (helps confirm Vault has the matching pubkey/JWKS)
PUBTMP="$(mktemp)"
openssl rsa -in "$PRIVKEY" -pubout > "$PUBTMP" 2>/dev/null
PK_FP="$(openssl rsa -pubin -in "$PUBTMP" -outform DER 2>/dev/null | openssl dgst -sha256 | sed 's/^.*= //')"
echo "Public key SHA256 fingerprint: $PK_FP"
rm -f "$PUBTMP"
echo

# Small helpers
b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
http() {  # curl wrapper: $1=method, $2=url, stdin body allowed
  curl -sS -w "\nHTTP_CODE:%{http_code}\n" -X "$1" "$2" -H 'Content-Type: application/json' --data-binary @-
}
vault_get() { # authenticated GET request to Vault
  curl -sS -H "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/$1"
}

# Check auth method and team roles configuration
echo "→ Checking JWT auth method and team roles configuration"
echo ""

# Check if auth method exists
AUTH_METHODS="$(vault_get "sys/auth" 2>/dev/null)" || AUTH_METHODS=""
if echo "$AUTH_METHODS" | jq -e ".\"jenkins-jwt/\"" >/dev/null 2>&1; then
    echo "   ✓ JWT auth method 'jenkins-jwt/' is enabled"
else
    echo "   ✗ JWT auth method 'jenkins-jwt/' not found"
    echo "     Run: vault auth enable -path=jenkins-jwt jwt"
    exit 1
fi

# Check team roles exist
echo "   Team roles configured:"
for team in "${TEAMS[@]}"; do
    ROLE_CHECK="$(vault_get "$AUTH_PATH/role/$team" 2>/dev/null)" || ROLE_CHECK=""
    if echo "$ROLE_CHECK" | jq -e '.data' >/dev/null 2>&1; then
        BOUND_CLAIMS=$(echo "$ROLE_CHECK" | jq -r '.data.bound_claims.selected_group // "none"')
        TOKEN_POLICIES=$(echo "$ROLE_CHECK" | jq -r '.data.token_policies[]? // "none"' | tr '\n' ',' | sed 's/,$//')
        echo "     ✓ $team → bound_claims: selected_group=$BOUND_CLAIMS, policies: $TOKEN_POLICIES"
    else
        echo "     ✗ $team → role not found"
    fi
done
echo

# Reusable header (JWS)
HJSON=$(jq -n --arg kid "$KID" '{alg:"RS256",typ:"JWT",kid:$kid}')
H=$(printf '%s' "$HJSON" | b64url)

create_and_login() {
  team="$1"; user="$2"; job="$3"

  echo "──▶ Testing team=$team user=$user job=$job"

  iat=$(date +%s); exp=$((iat+900)); build_id="demo-${iat}"

  payload=$(jq -n \
    --arg iss "$ISS" \
    --arg aud "$AUD" \
    --arg env "$ENV_CLAIM" \
    --arg selected_group "$team" \
    --arg job "$job" \
    --arg build "$build_id" \
    --arg user "$user" \
    --argjson iat "$iat" \
    --argjson exp "$exp" \
    '{
      iss:$iss, aud:$aud, iat:$iat, exp:$exp, env:$env,
      selected_group:$selected_group,
      jenkins_job:$job, build_id:$build, user_id:$user
    }')

  if [ "$DEBUG" = "1" ]; then
    echo "   jwt header:";  echo "$HJSON"   | jq .
    echo "   jwt payload:"; echo "$payload" | jq .
  fi

  P=$(printf '%s' "$payload" | b64url)
  SIG=$(printf '%s.%s' "$H" "$P" | openssl dgst -sha256 -sign "$PRIVKEY" -binary | b64url)
  JWT="$H.$P.$SIG"

  # Do the login via raw HTTP
  echo "   Authenticating with Vault..."
  BODY=$(jq -n --arg role "$team" --arg jwt "$JWT" '{role:$role, jwt:$jwt}')
  RESP="$(printf '%s' "$BODY" | http POST "$VAULT_ADDR/v1/$AUTH_PATH/login")"
  CODE="$(printf '%s' "$RESP" | awk -F: '/^HTTP_CODE:/{print $2}')"
  JSON="$(printf '%s' "$RESP" | sed '/^HTTP_CODE:/d')"

  if [ "$CODE" != "200" ]; then
    echo "   ✗ Login failed (HTTP $CODE)"
    if [ "$DEBUG" = "1" ]; then
      echo "   Response: $JSON"
    fi
    return 1
  fi

  token=$(printf '%s' "$JSON" | jq -r '.auth.client_token // empty')
  if [ -z "$token" ]; then
    echo "   ✗ No client_token in response"
    return 1
  fi

  ttl=$(printf '%s' "$JSON" | jq -r '.auth.lease_duration')
  entity_id=$(printf '%s' "$JSON" | jq -r '.auth.entity_id // "unknown"')
  echo "   ✓ Token issued (ttl: ${ttl}s, entity: ${entity_id:0:8}...)"
  printf '%s\n' "$token"
}

TOKENS=()
i=0
for t in "${TEAMS[@]}"; do
  case "$t" in
    mobile-developers)   u="mobile.user";   j="mobile-pipeline" ;;
    frontend-developers) u="frontend.user"; j="frontend-pipeline" ;;
    backend-developers)  u="backend.user";  j="backend-pipeline" ;;
    devops-team)         u="devops.user";   j="devops-pipeline" ;;
    *)                   u="demo.user";     j="demo-pipeline" ;;
  esac
  echo
  if tok=$(create_and_login "$t" "$u" "$j"); then
    TOKENS[$i]="$tok"
  else
    TOKENS[$i]=""
  fi
  i=$((i+1))
done

echo
echo "=== Results ==="
i=0
for t in "${TEAMS[@]}"; do
  tok="${TOKENS[$i]:-}"
  if [ -n "$tok" ]; then
    echo "  $t: OK (token length: ${#tok})"
  else
    echo "  $t: FAILED"
  fi
  i=$((i+1))
done
