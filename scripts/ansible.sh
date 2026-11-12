#!/usr/bin/env bash
# scripts/ansible.sh <playbook> [--check] [ansible-playbook args...]
# scripts/ansible.sh --version-check
#
# The only supported way to run Ansible here. Runs from the repo root with
# ansible.cfg. Ansible refuses non-blocking stdio (agent shells, some CI), so
# stdin comes from /dev/null and output goes through cat. Passes token file
# PATHS (vsync_tokens_dir), never a token, plus the non-secret lab settings in
# .build/ansible-vars.json. The vsync_stats callback writes the play recap
# counts to .build/ansible-stats/<playbook>[.check].json.
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname -- "$0")/common.sh"
cd "$VSYNC_ROOT"
export ANSIBLE_CONFIG="$VSYNC_ROOT/ansible.cfg"

if [ "${1:-}" = --version-check ]; then
  v=$(ansible-playbook --version </dev/null 2>&1 | cat | head -1)
  echo "$v"
  [[ "$v" == *"core 2.2"[1-9]* ]] || die "ansible-core 2.21 or later is required"
  exit 0
fi

playbook=${1:?Usage: ansible.sh <playbook> [--check] [args]}
shift
playbook=${playbook%.yml}
[ -f "ansible/$playbook.yml" ] || die "ansible: unknown playbook ansible/$playbook.yml"

mkdir -p "$BUILD_DIR/ansible-stats"
jq -n \
  --arg root "$VSYNC_ROOT" \
  --arg tokens "$VSYNC_STATE/tokens" \
  --arg state "$VSYNC_STATE" \
  --arg ca "$VAULT_CACERT" \
  --arg seal "https://127.0.0.1:$(vsync_conf VSYNC_PORT_VAULT_S)" \
  --argjson nodes "$(for n in vault-1 vault-2 vault-3; do jq -n --arg n "$n" --arg a "https://127.0.0.1:$(vault_port_of "$n")" '{($n): $a}'; done | jq -s add)" \
  --arg web "https://localhost:$(vsync_conf VSYNC_PORT_WEB)" \
  --arg namespace "$(vsync_conf VSYNC_NAMESPACE)" \
  --argjson session_idle "$(vsync_conf VSYNC_SESSION_IDLE)" \
  --arg gh_owner "$(vsync_conf VSYNC_GITHUB_OWNER)" --arg gh_repo "$(vsync_conf VSYNC_GITHUB_REPO)" \
  --arg gh_app_id "$(vsync_conf VSYNC_GITHUB_APP_ID)" --arg gh_app "$(vsync_conf VSYNC_GITHUB_APP_NAME)" \
  --arg gh_install "$(vsync_conf VSYNC_GITHUB_INSTALLATION_ID)" \
  --arg ls_url "https://localhost:$(vsync_conf VSYNC_PORT_LOCALSTACK)" --arg ls_ip "$(vsync_conf VSYNC_LOCALSTACK_IP)" \
  --arg region "$(vsync_conf VSYNC_AWS_REGION)" \
  '{vsync_root: $root, vsync_tokens_dir: $tokens, vsync_state_dir: $state, vsync_ca: $ca,
    vsync_seal_addr: $seal, vsync_node_addrs: $nodes, vsync_cluster_addr: $nodes["vault-1"],
    vsync_web_url: $web, vsync_namespace: $namespace,
    vsync_session_idle: $session_idle,
    vsync_github: {owner: $gh_owner, repo: $gh_repo, app_id: $gh_app_id, app: $gh_app, installation_id: $gh_install},
    vsync_localstack: {url: $ls_url, ip: $ls_ip, region: $region}}' >"$BUILD_DIR/ansible-vars.json"

# A user-run make root-regen leaves a root token file; bootstrap phases may
# use it (never revoke it: make root-revoke does) to re-apply a policy change.
if [ -n "${VSYNC_ROOT_FILE:-}" ]; then
  [ -s "$VSYNC_ROOT_FILE" ] || die "VSYNC_ROOT_FILE=$VSYNC_ROOT_FILE is not a file"
  jq --arg f "$(cd "$(dirname "$VSYNC_ROOT_FILE")" && pwd)/$(basename "$VSYNC_ROOT_FILE")" '. + {vsync_root_file: $f}' \
    "$BUILD_DIR/ansible-vars.json" >"$BUILD_DIR/ansible-vars.json.tmp" && mv "$BUILD_DIR/ansible-vars.json.tmp" "$BUILD_DIR/ansible-vars.json"
fi

export VSYNC_PHASE="$playbook" VSYNC_STATS_DIR="$BUILD_DIR/ansible-stats"
set -o pipefail
ansible-playbook "ansible/$playbook.yml" -e "@$BUILD_DIR/ansible-vars.json" "$@" </dev/null 2>&1 | cat
