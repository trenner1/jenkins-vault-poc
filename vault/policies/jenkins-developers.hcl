# Developer policy - read/write access to project-scoped secrets
# Access restricted to the project specified in token metadata
path "kv/data/+/apps/{{token.meta.project}}/*" {
  capabilities = ["create", "read", "update", "delete"]
}

path "kv/metadata/+/apps/{{token.meta.project}}/*" {
  capabilities = ["read", "list"]
}

# Legacy job-based paths for backward compatibility (project-scoped)
path "kv/data/jobs/{{token.meta.project}}/*" {
  capabilities = ["create", "read", "update", "delete"]
}

path "kv/metadata/jobs/{{token.meta.project}}/*" {
  capabilities = ["read", "list"]
}

# Child token management
path "auth/token/create/jenkins-child" { capabilities = ["update"] }
path "auth/token/lookup-self"          { capabilities = ["update"] }
path "auth/token/revoke-self"          { capabilities = ["update"] }
path "sys/capabilities-self"           { capabilities = ["update"] }