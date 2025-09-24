# DevOps Team policy - read/write access to devops-tools and admin access to other projects
path "kv/data/+/apps/devops-tools/*" {
  capabilities = ["create", "read", "update", "delete"]
}

path "kv/metadata/+/apps/devops-tools/*" {
  capabilities = ["read", "list"]
}

# Admin access to all other team projects for operational support
path "kv/data/+/apps/*" {
  capabilities = ["create", "read", "update", "delete"]
}

path "kv/metadata/+/apps/*" {
  capabilities = ["read", "list"]
}

# Legacy job-based paths for backward compatibility
path "kv/data/jobs/*" {
  capabilities = ["create", "read", "update", "delete"]
}

path "kv/metadata/jobs/*" {
  capabilities = ["read", "list"]
}

# Child token management
path "auth/token/create/jenkins-child" { capabilities = ["update"] }
path "auth/token/lookup-self"          { capabilities = ["update"] }
path "auth/token/revoke-self"          { capabilities = ["update"] }
path "sys/capabilities-self"           { capabilities = ["update"] }