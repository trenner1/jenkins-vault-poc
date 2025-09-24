# Frontend Developers policy - read/write access to frontend-app secrets only
path "kv/data/+/apps/frontend-app/*" {
  capabilities = ["create", "read", "update", "delete"]
}

path "kv/metadata/+/apps/frontend-app/*" {
  capabilities = ["read", "list"]
}

# Legacy job-based paths for backward compatibility
path "kv/data/jobs/frontend-app/*" {
  capabilities = ["create", "read", "update", "delete"]
}

path "kv/metadata/jobs/frontend-app/*" {
  capabilities = ["read", "list"]
}

# Child token management
path "auth/token/create/jenkins-child" { capabilities = ["update"] }
path "auth/token/lookup-self"          { capabilities = ["update"] }
path "auth/token/revoke-self"          { capabilities = ["update"] }
path "sys/capabilities-self"           { capabilities = ["update"] }