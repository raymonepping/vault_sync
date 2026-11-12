# Vault becomes the system of record here: Secrets Import writes the legacy
# secrets to kv/parcel/*, Secrets Sync pushes them out (D8: Terraform never
# holds a value).
resource "vault_mount" "kv" {
  provider    = vault.lumen
  path        = "kv"
  type        = "kv"
  options     = { version = "2" }
  description = "Lumen Parcel secrets (system of record)"
}
