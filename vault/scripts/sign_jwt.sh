#!/usr/bin/env bash
set -euo pipefail

PRIV=${PRIV:-../../keys/jenkins-oidc.key}
KID=${KID:-jenkins-dev-key-1}
ISS=${ISS:-http://localhost:8080}
AUD=${AUD:-vault}
GROUP=${1:?usage: sign_jwt.sh <selected_group>}

b64(){ openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# header
printf '{"alg":"RS256","typ":"JWT","kid":"%s"}' "$KID" > /tmp/h.json
H=$(b64 < /tmp/h.json)

# payload
IAT=$(date +%s); EXP=$((IAT+900))
jq -n \
  --arg iss "$ISS" \
  --arg aud "$AUD" \
  --arg grp "$GROUP" \
  --arg job "manual-test" \
  --arg build "demo-$IAT" \
  --arg user "cli@example.com" \
  --argjson iat "$IAT" --argjson exp "$EXP" \
  '{iss:$iss,aud:$aud,iat:$iat,exp:$exp,
    selected_group:$grp,
    jenkins_job:$job,build_id:$build,user:$user}' > /tmp/p.json
P=$(b64 < /tmp/p.json)

# sign
SIG=$(printf "%s.%s" "$H" "$P" | openssl dgst -sha256 -sign "$PRIV" -binary | b64)

# output token
echo "$H.$P.$SIG"
