# Developer policy - read/write access to job-scoped secrets
# Access to environment-based paths scoped by project
path "kv/data/+/apps/+/*" {
  capabilities = ["create", "read", "update", "delete"]
}

path "kv/metadata/+/apps/+/*" {
  capabilities = ["read", "list"]
}

# Legacy job-based paths for backward compatibility
path "kv/data/jobs/+/*" {
  capabilities = ["create", "read", "update", "delete"]
}

path "kv/metadata/jobs/+/*" {
  capabilities = ["read", "list"]
}

# Child token management
path "auth/token/create/jenkins-child" { capabilities = ["update"] }
path "auth/token/lookup-self"          { capabilities = ["update"] }
path "auth/token/revoke-self"          { capabilities = ["update"] }
path "sys/capabilities-self"           { capabilities = ["update"] }