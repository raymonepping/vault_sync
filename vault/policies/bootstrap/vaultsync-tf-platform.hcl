# vaultsync-tf-platform: Terraform root vault-platform on the cluster (D7, D8).
# Declared, plannable structure: the audit devices (root namespace), the
# namespace lumen and, inside it, the KV v2 and userpass mounts, the vsync-*
# ACL policies and the console's token role. It holds no credential and no
# story state: no secret read, no sync destination, no GitHub App, no token.
# Written complete in prompt 02: after root revocation nothing can widen it.
# A root-namespace token reaches lumen through lumen/-prefixed paths.

# ── Audit, root namespace (sudo: Vault requires it) ──────────────────────────
path "sys/audit" { capabilities = ["read", "sudo"] }
path "sys/audit/file" { capabilities = ["create", "read", "update", "delete", "sudo"] }
path "sys/audit/stdout" { capabilities = ["create", "read", "update", "delete", "sudo"] }

# ── The namespace ────────────────────────────────────────────────────────────
path "sys/namespaces" { capabilities = ["list"] }
path "sys/namespaces/lumen" { capabilities = ["create", "read", "update", "delete"] }

# ── Mounts and auth in lumen (enable, read and tune need sudo) ──────────────
path "lumen/sys/mounts" { capabilities = ["read"] }
path "lumen/sys/mounts/kv" { capabilities = ["create", "read", "update", "delete"] }
path "lumen/sys/mounts/kv/tune" { capabilities = ["read", "update"] }
path "lumen/kv/config" { capabilities = ["create", "read", "update"] }
path "lumen/sys/auth" { capabilities = ["read"] }
path "lumen/sys/auth/userpass" { capabilities = ["create", "read", "update", "delete", "sudo"] }
path "lumen/sys/auth/+/tune" { capabilities = ["read", "update", "sudo"] }
path "lumen/sys/mounts/auth/userpass" { capabilities = ["read"] }
path "lumen/sys/mounts/auth/token" { capabilities = ["read"] }
path "lumen/sys/mounts/auth/+/tune" { capabilities = ["read", "update", "sudo"] }
path "lumen/sys/auth/token" { capabilities = ["read"] }

# ── Token roles (the console's, the import's) ────────────────────────────────
path "lumen/auth/token/roles" { capabilities = ["list"] }
path "lumen/auth/token/roles/vsync-*" { capabilities = ["create", "read", "update", "delete"] }

# ── Policies: the story's vsync-* ACLs only ──────────────────────────────────
path "lumen/sys/policies/acl" { capabilities = ["list"] }
path "lumen/sys/policies/acl/vsync-*" { capabilities = ["create", "read", "update", "delete"] }
path "lumen/sys/policy/vsync-*" { capabilities = ["create", "read", "update", "delete"] }

# ── The provider ─────────────────────────────────────────────────────────────
path "auth/token/create" { capabilities = ["update"] }
path "auth/token/lookup-self" { capabilities = ["read"] }
path "sys/license/status" { capabilities = ["read"] }

# ── Never ────────────────────────────────────────────────────────────────────
path "lumen/kv/data/*" { capabilities = ["deny"] }
path "lumen/kv/metadata/*" { capabilities = ["deny"] }
path "sys/sync/*" { capabilities = ["deny"] }
path "lumen/sys/sync/*" { capabilities = ["deny"] }
path "lumen/auth/userpass/users/*" { capabilities = ["deny"] }
path "lumen/auth/token/create/*" { capabilities = ["deny"] }
path "sys/policies/acl/vaultsync-*" { capabilities = ["deny"] }
