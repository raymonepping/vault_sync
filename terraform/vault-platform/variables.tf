variable "vault_addr" {
  description = "The cluster on a published loopback port (scripts/tf.sh)."
  type        = string
}

variable "vault_cacert" {
  description = "The lab CA chain (vault-tls/ca-chain.pem)."
  type        = string
}

variable "namespace" {
  description = "The namespace every object of the story lives in (D9)."
  type        = string
  default     = "lumen"
}

variable "sync_secret" {
  description = "The one KV secret the story syncs (config/story.json sync.secret); the presenter may read it because Vault requires that to sync it."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]+(/[a-z0-9-]+)+$", var.sync_secret))
    error_message = "sync_secret is a lowercase KV path like parcel/delivery-api."
  }
}
