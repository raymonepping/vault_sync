#!/usr/bin/env bash
# scripts/github-evidence.sh (make github-evidence, D15): GitHub's own record
# of the repository's Actions secrets (names and update times; GitHub has no
# API for values) from the host's gh CLI into .build/github/evidence.json,
# which the API reads through a read-only directory mount. Written in place
# (same inode): after a rename the VM's shared folder answered ENOENT to every
# second read (measured). No GitHub credential ever reaches a container.
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname -- "$0")/common.sh"
umask 022 # after common.sh (077): the API's uid reads it
command -v gh >/dev/null || die "github-evidence: the gh CLI is not installed (brew install gh)"
repo="$(vsync_conf VSYNC_GITHUB_OWNER)/$(vsync_conf VSYNC_GITHUB_REPO)"
list=$(gh secret list -R "$repo" --json name,updatedAt) || die "github-evidence: gh secret list failed (gh auth status)"
mkdir -p "$BUILD_DIR/github"
jq --arg repo "$repo" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{repo: $repo, read_at: $at, secrets: [.[] | select(.name | startswith("LUMEN_")) | {name, updated_at: .updatedAt}]}' \
  <<<"$list" >"$BUILD_DIR/github/evidence.json.tmp"
cat "$BUILD_DIR/github/evidence.json.tmp" >"$BUILD_DIR/github/evidence.json"
rm -f "$BUILD_DIR/github/evidence.json.tmp"
echo "github-evidence: $(jq '.secrets | length' "$BUILD_DIR/github/evidence.json") LUMEN_ secret(s) in $repo"
