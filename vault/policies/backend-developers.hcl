# Backend Developers policy - read/write access to backend-service secrets only
path "kv/data/+/apps/backend-service/*" {
  capabilities = ["create", "read", "update", "delete"]
}

path "kv/metadata/+/apps/backend-service/*" {
  capabilities = ["read", "list"]
}

# Legacy job-based paths for backward compatibility
path "kv/data/jobs/backend-service/*" {
  capabilities = ["create", "read", "update", "delete"]
}

path "kv/metadata/jobs/backend-service/*" {
  capabilities = ["read", "list"]
}

# Child token management
path "auth/token/create/jenkins-child" { capabilities = ["update"] }
path "auth/token/lookup-self"          { capabilities = ["update"] }
path "auth/token/revoke-self"          { capabilities = ["update"] }
path "sys/capabilities-self"           { capabilities = ["update"] }