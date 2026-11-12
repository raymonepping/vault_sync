#!/usr/bin/env bash
# scripts/backup.sh: Raft snapshots of vault-s and the cluster, LocalStack's
# state, plus .secrets, into backups/<timestamp>/ (0700). Scoped tokens only: ansible-seal and
# ansible-platform hold sys/storage/raft/snapshot read (bootstrap policies).
set -euo pipefail
umask 077
# shellcheck source=scripts/common.sh
source "$(dirname -- "$0")/common.sh"
cd "$VSYNC_ROOT"

dest="backups/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$dest"
chmod 700 backups "$dest"
vault_node vault-s
vault_token ansible-seal
vault operator raft snapshot save "$dest/vault-s.snap"
unset VAULT_TOKEN
vault_active
vault_token ansible-platform
vault operator raft snapshot save "$dest/cluster.snap"
unset VAULT_TOKEN
# LocalStack's state: its own volume, copied as a tarball (LocalStack keeps
# serving; Secrets Manager writes are rare between acts).
if [ "$(vsync_container_state vaultsync-localstack)" = running ]; then
  podman exec vaultsync-localstack tar -C /var/lib/localstack -czf - state >"$dest/localstack-state.tgz" 2>/dev/null ||
    echo "backup: LocalStack's state could not be copied (podman logs vaultsync-localstack)"
fi
# Not .secrets/legacy (credentials of a cluster clean-slate removed) and not
# Terraform's provider cache (a re-downloadable binary).
tar -C "$VSYNC_ROOT" --exclude '.secrets/legacy' --exclude '*/.terraform' -czf "$dest/secrets.tgz" .secrets
echo "backup: $dest (vault-s.snap, cluster.snap, localstack-state.tgz, secrets.tgz)"
du -sh "$dest" | awk '{print "backup: " $1}'
