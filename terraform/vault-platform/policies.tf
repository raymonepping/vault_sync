resource "vault_policy" "presenter" {
  provider = vault.lumen
  name     = "vsync-presenter"
  policy   = templatefile("${path.module}/policies/presenter.hcl.tftpl", { sync_secret = var.sync_secret })
}
