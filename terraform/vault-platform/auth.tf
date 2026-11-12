# Ines signs in here (D13). Ansible creates her user and password (runtime
# state, D8); the policy below is all she holds.
resource "vault_auth_backend" "userpass" {
  provider    = vault.lumen
  type        = "userpass"
  path        = "userpass"
  description = "Lumen Parcel people"
}
