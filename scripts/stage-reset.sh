#!/usr/bin/env bash
# scripts/stage-reset.sh (make stage-reset, D18): after a rehearsal or a show.
# Removes every association of the two destinations (Vault deletes the copies
# in GitHub and LocalStack), deletes the imported kv/parcel/* paths, creates
# any legacy secret that is missing in LocalStack, and asks the API to clear
# its event list. Vault's audit files are never edited. CONFIRM=yes skips the
# question.
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname -- "$0")/common.sh"
cd "$VSYNC_ROOT"
answer=${CONFIRM:-}
if [ "$answer" != yes ]; then
  printf 'This removes the synced copies in GitHub and LocalStack and the imported KV paths. Type yes: '
  read -r answer
fi
[ "$answer" = yes ] || {
  echo "Aborted."
  exit 1
}
for p in stage-reset seed stage; do
  ./scripts/ansible.sh "$p" >"$BUILD_DIR/stage-reset-$p.log" 2>&1 || {
    cat "$BUILD_DIR/stage-reset-$p.log" >&2
    die "stage-reset: ansible $p failed"
  }
done
if [ "$(vsync_container_state vaultsync-api)" = running ]; then
  podman kill --signal USR2 vaultsync-api >/dev/null || die "stage-reset: the API could not clear its event list (podman logs vaultsync-api)"
else
  echo "stage-reset: the API is not running, so its event list was not cleared (it starts empty anyway)"
fi
echo "stage-reset: associations removed, imported paths deleted, legacy store in place"
