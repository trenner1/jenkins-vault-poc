# Mobile Developers policy - read/write access to mobile-app secrets only
path "kv/data/+/apps/mobile-app/*" {
  capabilities = ["create", "read", "update", "delete"]
}

path "kv/metadata/+/apps/mobile-app/*" {
  capabilities = ["read", "list"]
}

# Legacy job-based paths for backward compatibility
path "kv/data/jobs/mobile-app/*" {
  capabilities = ["create", "read", "update", "delete"]
}

path "kv/metadata/jobs/mobile-app/*" {
  capabilities = ["read", "list"]
}

# Child token management
path "auth/token/create/jenkins-child" { capabilities = ["update"] }
path "auth/token/lookup-self"          { capabilities = ["update"] }
path "auth/token/revoke-self"          { capabilities = ["update"] }
path "sys/capabilities-self"           { capabilities = ["update"] }