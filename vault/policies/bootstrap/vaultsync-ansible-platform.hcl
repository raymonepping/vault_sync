# vaultsync-ansible-platform: Ansible on the cluster (D7, D8). Order and
# moment: the GitHub App registration and both sync destinations (they hold
# or reference credentials), the KV values it seeds and resets, the
# presenter's login, the console and import tokens, the secrets-import
# activation flag, the stage reset, Raft health and snapshots, and the
# read-only checks of validate, verify and doctor.
# It may NOT create a mount or write a policy, and it never reads a value.
# Written complete in prompt 02: after root revocation nothing can widen it.
# Secrets Sync lives in the root namespace or in lumen (the probe decides):
# both are granted; sys/ paths carry sudo where Vault may require it.

# ── Secrets Sync: the GitHub App, destinations, associations, config ────────
path "sys/sync/github-apps" { capabilities = ["list", "sudo"] }
path "sys/sync/github-apps/*" { capabilities = ["create", "read", "update", "delete", "sudo"] }
path "sys/sync/destinations" { capabilities = ["list", "read", "sudo"] }
path "sys/sync/destinations/*" { capabilities = ["create", "read", "update", "delete", "list", "sudo"] }
path "sys/sync/associations" { capabilities = ["list", "read", "sudo"] }
path "sys/sync/associations/*" { capabilities = ["read", "list", "sudo"] }
path "sys/sync/config" { capabilities = ["read", "sudo"] }
path "lumen/sys/sync/github-apps" { capabilities = ["list", "sudo"] }
path "lumen/sys/sync/github-apps/*" { capabilities = ["create", "read", "update", "delete", "sudo"] }
path "lumen/sys/sync/destinations" { capabilities = ["list", "read", "sudo"] }
path "lumen/sys/sync/destinations/*" { capabilities = ["create", "read", "update", "delete", "list", "sudo"] }
path "lumen/sys/sync/associations" { capabilities = ["list", "read", "sudo"] }
path "lumen/sys/sync/associations/*" { capabilities = ["read", "list", "sudo"] }

# ── Secrets Import: the activation flag (root namespace) ─────────────────────
path "sys/activation-flags" { capabilities = ["read", "sudo"] }
path "sys/activation-flags/*" { capabilities = ["create", "read", "update", "sudo"] }

# ── KV: the story's paths (written by seed/reset, never read as values) ─────
path "lumen/kv/data/parcel/*" { capabilities = ["create", "update", "delete"] }
path "lumen/kv/metadata/parcel/*" { capabilities = ["create", "read", "update", "delete", "list"] }
path "lumen/kv/metadata/parcel" { capabilities = ["list"] }
path "lumen/kv/data/canary/*" { capabilities = ["create", "update", "delete"] }
path "lumen/kv/metadata/canary/*" { capabilities = ["read", "delete", "list"] }

# ── People: the presenter's userpass user ────────────────────────────────────
path "lumen/auth/userpass/users" { capabilities = ["list"] }
path "lumen/auth/userpass/users/ines" { capabilities = ["create", "read", "update"] }

# ── Tokens from Terraform's roles (sudo: minting into a child namespace from
#    a root-namespace token needs it, measured in vault_governor) ──────────
path "lumen/auth/token/create/vsync-*" { capabilities = ["update", "sudo"] }
path "lumen/auth/token/lookup" { capabilities = ["update"] }
path "lumen/auth/token/lookup-accessor" { capabilities = ["update"] }
path "lumen/auth/token/revoke-accessor" { capabilities = ["update"] }
path "lumen/auth/token/roles/*" { capabilities = ["read"] }

# ── Cluster operations ───────────────────────────────────────────────────────
path "sys/storage/raft/configuration" { capabilities = ["read"] }
path "sys/storage/raft/snapshot" { capabilities = ["read"] }
path "sys/step-down" { capabilities = ["update", "sudo"] }
path "sys/license/status" { capabilities = ["read"] }
path "sys/health" { capabilities = ["read"] }
path "auth/token/lookup" { capabilities = ["update"] }

# ── Read-only checks (validate, verify, doctor) ──────────────────────────────
path "sys/audit" { capabilities = ["read", "sudo"] }
path "sys/namespaces" { capabilities = ["list"] }
path "sys/namespaces/lumen" { capabilities = ["read"] }
path "lumen/sys/mounts" { capabilities = ["read"] }
path "lumen/sys/auth" { capabilities = ["read"] }
path "lumen/sys/policies/acl/vsync-*" { capabilities = ["read"] }

# Break glass (make root-regen): Vault 2.0 requires a token as well as the
# key share for sys/generate-root (HCSEC-2026-08). root-regen.sh sends this token.
path "sys/generate-root/*" { capabilities = ["create", "read", "update", "delete", "sudo"] }

# ── Never ────────────────────────────────────────────────────────────────────
path "lumen/sys/mounts/*" { capabilities = ["deny"] }
path "sys/mounts/*" { capabilities = ["deny"] }
path "sys/policies/acl/vaultsync-*" { capabilities = ["deny"] }
