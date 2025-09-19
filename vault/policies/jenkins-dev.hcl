# KV v2: job-scoped read (data endpoint)
path "kv/data/dev/apps/{{identity.entity.aliases.auth_jwt_5f35b701.metadata.job}}/*" {
  capabilities = ["read"]
}

# KV v2: allow listing only within THIS job's folder (metadata endpoint)
path "kv/metadata/dev/apps/{{identity.entity.aliases.auth_jwt_5f35b701.metadata.job}}" {
  capabilities = ["list"]
}
path "kv/metadata/dev/apps/{{identity.entity.aliases.auth_jwt_5f35b701.metadata.job}}/*" {
  capabilities = ["list"]
}

# Child token management (role-scoped, no generic create)
path "auth/token/create/jenkins-child" { capabilities = ["update"] }

# Lookup/revoke for the child token (both are POST → update)
path "auth/token/lookup-self"          { capabilities = ["update"] }
path "auth/token/revoke-self"          { capabilities = ["update"] }

# Useful for the pipeline's capability probe
path "sys/capabilities-self"           { capabilities = ["update"] }
