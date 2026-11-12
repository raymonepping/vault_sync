#!/usr/bin/env bash
# scripts/app-build.sh [api|web ...]: build the app images (arm64). The build
# context is staged to $TMPDIR: macOS TCC can refuse Podman reads under
# ~/Documents, and xattrs break builds. The API image carries
# config/story.json without the legacy values.
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname -- "$0")/common.sh"
export COPYFILE_DISABLE=1

targets=${*:-api web}
prefix=$(vsync_conf VSYNC_IMAGE_PREFIX)
tag=$(vsync_conf VSYNC_IMAGE_TAG)

for t in $targets; do
  ctx=$(mktemp -d "${TMPDIR:-/tmp}/vaultsync-$t.XXXXXX")
  case "$t" in
  api)
    rsync -a --exclude node_modules --exclude test --exclude '._*' --exclude .DS_Store "$VSYNC_ROOT/api/" "$ctx/"
    mkdir -p "$ctx/config"
    node "$VSYNC_ROOT/scripts/story-check.js" >/dev/null
    # The API never needs the legacy values: they stay out of the image.
    jq 'del(.legacy[].value)' "$VSYNC_ROOT/config/story.json" >"$ctx/config/story.json"
    while IFS= read -r v; do
      ! grep -rqF -- "$v" "$ctx" || die "app-build: a legacy value reached the API image"
    done < <(jq -r '.legacy[].value' "$VSYNC_ROOT/config/story.json")
    ;;
  web)
    rsync -a --exclude node_modules --exclude dist --exclude test --exclude '._*' --exclude .DS_Store "$VSYNC_ROOT/web/" "$ctx/"
    ;;
  *)
    echo "app-build: unknown target '$t'" >&2
    exit 64
    ;;
  esac
  xattr -rc "$ctx" 2>/dev/null || true
  # common.sh sets umask 077; the images run as non-root users that must read
  # these files.
  chmod -R a+rX "$ctx"
  echo "app-build: building $prefix/$t:$tag"
  podman build -q --format docker --platform linux/arm64 \
    --build-arg NODE_IMAGE="$(vsync_conf NODE_IMAGE)" \
    --build-arg NGINX_IMAGE="$(vsync_conf NGINX_IMAGE)" \
    --build-arg VAULT_ENT_IMAGE="$(vsync_conf VAULT_ENT_IMAGE)" \
    -t "$prefix/$t:$tag" -f "$ctx/Containerfile" "$ctx" >/dev/null
  rm -rf "$ctx"
  arch=$(podman image inspect "$prefix/$t:$tag" --format '{{.Architecture}}')
  [ "$arch" = arm64 ] || {
    echo "app-build: $t is $arch, not arm64" >&2
    exit 1
  }
done
