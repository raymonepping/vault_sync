output "namespace" {
  value = vault_namespace.lumen.path_fq
}

output "userpass_accessor" {
  value = vault_auth_backend.userpass.accessor
}

output "kv_accessor" {
  value = vault_mount.kv.accessor
}

output "policies" {
  value = sort([vault_policy.presenter.name])
}
