#!/usr/bin/env bash
# scripts/boundary-check.sh (make boundary): prove the Terraform/Ansible
# boundary Vault enforces (golden_ticket's format). Each scoped token asks
# sys/capabilities-self what it may do on paths it must and must not touch.
# Never prints a token. Rows: token|vault|path|allow:cap or deny:cap.
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname -- "$0")/common.sh"

checks=(
  # vault-s (prompt 02)
  "tf-seal|seal|sys/mounts/transit|allow:create"
  "tf-seal|seal|auth/token/roles/autounseal|allow:update"
  "tf-seal|seal|sys/audit/file|allow:sudo"
  "tf-seal|seal|auth/token/create/autounseal|deny:update"
  "tf-seal|seal|sys/policies/acl/vaultsync-tf-seal|deny:update"
  "ansible-seal|seal|auth/token/create/autounseal|allow:update"
  "ansible-seal|seal|auth/token/roles/autounseal|deny:update"
  "ansible-seal|seal|sys/policies/acl/autounseal|deny:update"
  "ansible-seal|seal|sys/mounts/transit|deny:create"
  "ansible-seal|seal|sys/policies/acl/vaultsync-ansible-seal|deny:update"
  # the cluster: tool tokens (prompt 02). A root-namespace token reaches
  # namespace lumen through lumen/ paths.
  "tf-platform|vault|sys/namespaces/lumen|allow:create"
  "tf-platform|vault|sys/audit/file|allow:sudo"
  "tf-platform|vault|lumen/sys/mounts/kv|allow:create"
  "tf-platform|vault|lumen/sys/auth/userpass|allow:sudo"
  "tf-platform|vault|lumen/sys/policies/acl/vsync-console|allow:update"
  "tf-platform|vault|lumen/auth/token/roles/vsync-console|allow:update"
  "tf-platform|vault|lumen/kv/data/parcel/delivery-api|deny:read"
  "tf-platform|vault|sys/sync/destinations/gh/lumen-github|deny:update"
  "tf-platform|vault|lumen/sys/sync/destinations/gh/lumen-github|deny:update"
  "tf-platform|vault|sys/sync/github-apps/vaultsyncdemo|deny:update"
  "tf-platform|vault|lumen/auth/userpass/users/ines|deny:update"
  "tf-platform|vault|lumen/auth/token/create/vsync-console|deny:update"
  "tf-platform|vault|sys/policies/acl/vaultsync-tf-platform|deny:update"
  "ansible-platform|vault|sys/sync/github-apps/vaultsyncdemo|allow:update"
  "ansible-platform|vault|sys/sync/destinations/gh/lumen-github|allow:update"
  "ansible-platform|vault|lumen/sys/sync/destinations/aws-sm/lumen-aws|allow:update"
  "ansible-platform|vault|sys/activation-flags/secrets-import/activate|allow:update"
  "ansible-platform|vault|lumen/kv/data/parcel/delivery-api|allow:create"
  "ansible-platform|vault|lumen/kv/data/parcel/delivery-api|deny:read"
  "ansible-platform|vault|lumen/auth/userpass/users/ines|allow:update"
  "ansible-platform|vault|lumen/auth/token/create/vsync-console|allow:update"
  "ansible-platform|vault|lumen/sys/mounts/kv|deny:create"
  "ansible-platform|vault|lumen/sys/policies/acl/vsync-console|deny:update"
  "ansible-platform|vault|sys/policies/acl/vaultsync-ansible-platform|deny:update"
)

fails=0
checked=0
skipped=0
for check in "${checks[@]}"; do
  IFS='|' read -r name cluster path expect <<<"$check"
  file="$VSYNC_STATE/tokens/$name"
  if [ ! -s "$file" ]; then
    skipped=$((skipped + 1))
    continue
  fi
  if [ "$cluster" = seal ]; then vault_node vault-s; else vault_cluster; fi
  caps=$(vcurl "$(cat "$file")" -sS --cacert "$VAULT_CACERT" \
    -X POST -d "{\"paths\":[\"$path\"]}" "$VAULT_ADDR/v1/sys/capabilities-self" |
    jq -r --arg p "$path" 'if .errors then "ERROR" else ((.data // .)[$p] // [] | join(",")) end')
  mode=${expect%%:*}
  cap=${expect#*:}
  if [ "$caps" = ERROR ]; then
    # A refused question proves nothing, also not a deny.
    printf '  \033[31mFAIL\033[0m %-17s %-5s %-6s %s (capabilities-self refused)\n' "${who:-$name}" "$mode" "$cap" "$path"
    fails=$((fails + 1))
    checked=$((checked + 1))
    continue
  fi
  has=no
  [[ ",$caps," == *",$cap,"* || ",$caps," == *",root,"* ]] && has=yes
  if { [ "$mode" = allow ] && [ "$has" = yes ]; } || { [ "$mode" = deny ] && [ "$has" = no ]; }; then
    printf '  \033[32mok\033[0m   %-17s %-5s %-6s %s\n' "$name" "$mode" "$cap" "$path"
  else
    printf '  \033[31mFAIL\033[0m %-17s %-5s %-6s %s (has: %s)\n' "$name" "$mode" "$cap" "$path" "${caps:-none}"
    fails=$((fails + 1))
  fi
  checked=$((checked + 1))
done
# ── The presenter in namespace lumen (D13) ───────────────────────────────────
# who|path|allow:cap or deny:cap. Ines writes values and never reads one,
# moves only the lab's two destinations, never touches the app or a policy.
ns=$(vsync_conf VSYNC_NAMESPACE)
people_checks=(
  "ines|kv/data/parcel/delivery-api|allow:create"
  "ines|kv/data/parcel/delivery-api|allow:update"
  "ines|kv/data/parcel/delivery-api|allow:read"
  "ines|kv/data/parcel/smtp-relay|deny:read"
  "ines|kv/data/parcel/label-printer|deny:read"
  "ines|kv/data/other/x|deny:create"
  "ines|kv/metadata/parcel/delivery-api|allow:read"
  "ines|kv/metadata/parcel/delivery-api|deny:delete"
  "ines|sys/sync/destinations/gh/lumen-github/associations/set|allow:update"
  "ines|sys/sync/destinations/aws-sm/lumen-localstack/associations/remove|allow:update"
  "ines|sys/sync/destinations/gh/lumen-github|deny:update"
  "ines|sys/sync/destinations/gh/lumen-github|deny:delete"
  "ines|sys/sync/destinations/gh/other/associations/set|deny:update"
  "ines|sys/sync/github-apps/vaultsyncdemo|deny:read"
  "ines|sys/policies/acl/vsync-presenter|deny:update"
  "ines|auth/userpass/users/ines|deny:update"
)
vault_cluster
for check in "${people_checks[@]}"; do
  IFS='|' read -r who path expect <<<"$check"
  if [ ! -s "$VSYNC_ROOT/.secrets/people/$who" ]; then skipped=$((skipped + 1)); continue; fi
  person_login "$who" || { fails=$((fails + 1)); checked=$((checked + 1)); continue; }
  tok=$VAULT_TOKEN
  unset VAULT_TOKEN
  caps=$(vcurl "$tok" -sS --cacert "$VAULT_CACERT" -H "X-Vault-Namespace: $ns" \
    -X POST -d "{\"paths\":[\"$path\"]}" "$VAULT_ADDR/v1/sys/capabilities-self" |
    jq -r --arg p "$path" 'if .errors then "ERROR" else ((.data // .)[$p] // [] | join(",")) end')
  vcurl "$tok" -sS -o /dev/null --cacert "$VAULT_CACERT" -H "X-Vault-Namespace: $ns" \
    -X POST "$VAULT_ADDR/v1/auth/token/revoke-self" || true
  unset tok
  mode=${expect%%:*}
  cap=${expect#*:}
  if [ "$caps" = ERROR ]; then
    # A refused question proves nothing, also not a deny.
    printf '  \033[31mFAIL\033[0m %-17s %-5s %-6s %s (capabilities-self refused)\n' "${who:-$name}" "$mode" "$cap" "$path"
    fails=$((fails + 1))
    checked=$((checked + 1))
    continue
  fi
  has=no
  [[ ",$caps," == *",$cap,"* || ",$caps," == *",root,"* ]] && has=yes
  if { [ "$mode" = allow ] && [ "$has" = yes ]; } || { [ "$mode" = deny ] && [ "$has" = no ]; }; then
    printf '  \033[32mok\033[0m   %-17s %-5s %-6s %s\n' "$who" "$mode" "$cap" "$path"
  else
    printf '  \033[31mFAIL\033[0m %-17s %-5s %-6s %s (has: %s)\n' "$who" "$mode" "$cap" "$path" "${caps:-none}"
    fails=$((fails + 1))
  fi
  checked=$((checked + 1))
done
mkdir -p "$BUILD_DIR/gates"
jq -n --arg result "$([ "$fails" -eq 0 ] && echo pass || echo fail)" --argjson checked "$checked" \
  --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{gate: "boundary", result: $result, checks: $checked, at: $at}' >"$BUILD_DIR/gates/boundary.json"
[ "$fails" -eq 0 ] || die "$fails boundary check(s) failed."
[ "$checked" -gt 0 ] || die "no scoped token found: run make lab"
note=""
[ "$skipped" -eq 0 ] || note=", $skipped skipped: token not issued yet"
info "Token boundary holds ($checked checks$note)"
