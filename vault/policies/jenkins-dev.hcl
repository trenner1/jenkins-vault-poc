# List limited prefixes 
path "kv/metadata/dev/apps/" {
    capabilities = ["list"]
}

# Job-scoped reads via token.meta.job
path "kv/data/dev/apps/{{token.meta.job}}/*" {
    capabilities = ["read"]
}
