#!/usr/bin/env bash
# scripts/network.sh: create the shared network if it does not exist, on the
# fixed subnet of config/defaults.conf (Vault reaches LocalStack at a known
# address, so the sync destination's network allowlist can name one /32).
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname -- "$0")/common.sh"
podman network exists vaultsync-internal ||
  podman network create --label io.vaultsync.project=vault_sync --subnet "$(vsync_conf VSYNC_SUBNET)" vaultsync-internal >/dev/null
