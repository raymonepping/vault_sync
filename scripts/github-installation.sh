#!/usr/bin/env bash
# scripts/github-installation.sh (make github-installation): the GitHub App's
# installation on the lab's repository (its id, repository selection and
# permissions), for VSYNC_GITHUB_INSTALLATION_ID in config/defaults.conf.
# Identifiers only: the app JWT is signed in memory and never printed.
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname -- "$0")/common.sh"
pem=$(find "$VSYNC_ROOT/.secrets/github" -name '*.pem' -type f 2>/dev/null | head -1)
[ -n "$pem" ] || die "github-installation: no private key in .secrets/github/ (generate one in the app's settings)"
node "$VSYNC_ROOT/scripts/github-installation.js" "$pem" "$(vsync_conf VSYNC_GITHUB_APP_ID)" \
  "$(vsync_conf VSYNC_GITHUB_OWNER)" "$(vsync_conf VSYNC_GITHUB_REPO)"
