#!/usr/bin/env bash
set -euo pipefail
: "${VAULT_ADDR:?set VAULT_ADDR}"; : "${VAULT_TOKEN:?set VAULT_TOKEN}"
JOB="${1:-MyDemoJob}"
vault kv put "kv/dev/apps/${JOB}/example" user=alice pass=devpass123
echo "Seeded kv/dev/apps/${JOB}/example"
