#!/usr/bin/env bash
# scripts/probe.sh (make probe): measure what Vault 2.2.1 Secrets Sync and
# Secrets Import actually do against GitHub (the VaultSyncDemo app) and
# LocalStack before anything is built on them (prompt 03, questions 1 to 7 of
# prompts/00_brief.md). Scratch only: a namespace probe-<epoch>, a root KV
# mount probe-kv, sync objects named probe-*, one disposable GitHub secret
# named PROBE_*, LocalStack secrets under probe-<epoch>/. All removed at the
# end, also on failure (KEEP=1 keeps them). Runs on the 4h probe token that
# bootstrap minted, never a root token. Synthetic values only; no value, key
# or token is printed. Writes docs/capabilities.md and .build/probe/results.json.
set -euo pipefail
umask 077
# shellcheck source=scripts/common.sh
source "$(dirname -- "$0")/common.sh"
# shellcheck source=scripts/probe-lib.sh
source "$VSYNC_ROOT/scripts/probe-lib.sh"
cd "$VSYNC_ROOT"

OUT="$VSYNC_ROOT/docs/capabilities.md"
ROWS=$(mktemp)
NOTES=$(mktemp)
WORK=$(mktemp -d)
pass=0
fail=0
T=$(cat "$VSYNC_STATE/tokens/probe" 2>/dev/null) || die "probe: no probe token (.secrets/vault/tokens/probe); bootstrap mints one, make root-regen re-mints"
vault_active
api "$T" GET auth/token/lookup-self
[ "$ST" = 200 ] || die "probe: the probe token is not accepted (expired after 4h?): HTTP $ST $ERR"
note() { printf -- '- %s\n' "$*" >>"$NOTES"; }
yes_if() { if eval "$1"; then echo yes; else echo no; fi; }
EPOCH=$(date +%s)
NS="probe-$EPOCH"
OWNER=$(vsync_conf VSYNC_GITHUB_OWNER)
REPO=$(vsync_conf VSYNC_GITHUB_REPO)
APP_ID=$(vsync_conf VSYNC_GITHUB_APP_ID)
INSTALL=$(vsync_conf VSYNC_GITHUB_INSTALLATION_ID)
PEM=$(find "$VSYNC_ROOT/.secrets/github" -name '*.pem' -type f | head -1)
LS_IP=$(vsync_conf VSYNC_LOCALSTACK_IP)
LS="https://localhost:$(vsync_conf VSYNC_PORT_LOCALSTACK)"
REGION=$(vsync_conf VSYNC_AWS_REGION)
APP="probe-app-$EPOCH"
GH_DEST="probe-gh-$EPOCH"
AWS_DEST="probe-aws-$EPOCH"
PREFIX="PROBE_$EPOCH"

# aws_sm <Action> <json>: one AWS Secrets Manager call to LocalStack (JSON
# protocol, synthetic credentials, TLS verified against the lab CA). Sets
# AST (status) and ABODY. LocalStack accepts any signature for test keys.
aws_sm() {
  local out
  out=$(mktemp)
  AST=$(curl -sS -o "$out" -w '%{http_code}' --cacert "$VAULT_CACERT" -X POST "$LS/" \
    -H "X-Amz-Target: secretsmanager.$1" -H 'Content-Type: application/x-amz-json-1.1' \
    -H "Authorization: AWS4-HMAC-SHA256 Credential=test/20260101/$REGION/secretsmanager/aws4_request, SignedHeaders=host, Signature=0" \
    --data "$2" || echo 000)
  ABODY=$(cat "$out")
  rm -f "$out"
}
# fp <string>: the first 8 hex of SHA-256 (how the lab shows a value).
fp() { printf '%s' "$1" | shasum -a 256 | cut -c1-8; }
# gh_names: the repository's Actions secret names (metadata only).
gh_secrets() { gh secret list -R "$OWNER/$REPO" --json name,updatedAt 2>/dev/null || echo '[]'; }
# wait_status <ns prefix or ""> <type> <dest> <mount (unused)> <secret> <want regex> [tries]:
# poll the destination's associations until the secret's sync_status matches.
STATUS=""
wait_status() {
  local p=$1 type=$2 dest=$3 secret=$5 want=$6 tries=${7:-30} i
  for ((i = 0; i < tries; i++)); do
    api "$T" GET "${p}sys/sync/destinations/$type/$dest/associations"
    STATUS=$(jq -r --arg s "$secret" '[.data.associated_secrets // {} | to_entries[] | select(.value.secret_name == $s) | .value.sync_status] | first // "absent"' <<<"$BODY")
    [[ "$STATUS" =~ ^($want)$ ]] && return 0
    sleep 2
  done
  return 1
}

cleanup() {
  set +e
  if [ "${KEEP:-0}" = 1 ]; then
    echo "probe: KEEP=1, scratch objects kept"
  else
    for p in "" "$NS/"; do
      for m in probe-kv kv; do
        api "$T" POST "${p}sys/sync/destinations/gh/$GH_DEST/associations/remove" "$(jq -n --arg m "$m" '{mount: $m, secret_name: "canary"}')"
        api "$T" POST "${p}sys/sync/destinations/aws-sm/$AWS_DEST/associations/remove" "$(jq -n --arg m "$m" '{mount: $m, secret_name: "canary"}')"
      done
      sleep 3
      for d in "$GH_DEST" "$GH_DEST-raw" "$GH_DEST-safe"; do
        api "$T" POST "${p}sys/sync/destinations/gh/$d/associations/remove" "$(jq -n '{mount: "kv", secret_name: "parcel/delivery-api"}')"
      done
      sleep 3
      for d in "$GH_DEST" "$GH_DEST-raw" "$GH_DEST-safe"; do api "$T" DELETE "${p}sys/sync/destinations/gh/$d"; done
      api "$T" DELETE "${p}sys/sync/destinations/aws-sm/$AWS_DEST"
      api "$T" DELETE "${p}sys/sync/github-apps/$APP"
    done
    api "$T" DELETE sys/mounts/probe-kv
    api "$T" DELETE "sys/namespaces/$NS"
    aws_sm ListSecrets '{"MaxResults":100}'
    for n in $(jq -r --arg p "probe-$EPOCH/" '.SecretList[]?.Name | select(startswith($p) or startswith("vault/") and contains("probe"))' <<<"$ABODY" 2>/dev/null); do
      aws_sm DeleteSecret "$(jq -n --arg n "$n" '{SecretId: $n, ForceDeleteWithoutRecovery: true}')"
    done
  fi
  set -e
}
trap 'cleanup; rm -rf "$ROWS" "$NOTES" "$WORK"' EXIT

started=$(date +%s)
echo "probe: scratch namespace $NS, sync objects probe-*-$EPOCH"
[ -n "$INSTALL" ] || die "probe: VSYNC_GITHUB_INSTALLATION_ID is not set in config/defaults.conf"
[ -s "$PEM" ] || die "probe: no GitHub App private key in .secrets/github/"

# ── Q1: the licence ───────────────────────────────────────────────────────────
api "$T" GET sys/license/status
note "Licence features: $(jq -r '.data.autoloaded.features // [] | join(", ")' <<<"$BODY")."
for f in "Secrets Sync" "Secrets Import" "Namespaces"; do
  if jq -e --arg f "$f" '.data.autoloaded.features // [] | index($f)' <<<"$BODY" >/dev/null; then
    row P1 Q1 "sys/license/status has $f" listed listed yes
  else row P1 Q1 "sys/license/status has $f" listed missing no; fi
done
api "$T" PUT sys/activation-flags/secrets-sync/activate '{}'
row P2 Q2 "activate secrets-sync (every sys/sync call is 403 until then)" "200 or 204" "HTTP $ST${ERR:+: $ERR}" "$(yes_if '[[ "$ST" =~ ^20[04]$ ]]')"
api "$T" GET sys/sync/config
row P2 Q2 "sys/sync/config (root)" "200, disabled false" "HTTP $ST $(jq -c '.data // {}' <<<"$BODY")" "$(yes_if '[ "$ST" = 200 ]')"

# ── Structure: a scratch namespace with KV, and a root KV ─────────────────────
api "$T" POST "sys/namespaces/$NS" '{}'
[ "$ST" = 200 ] || die "probe: could not create $NS: HTTP $ST $ERR"
api "$T" POST "$NS/sys/mounts/kv" '{"type":"kv","options":{"version":"2"}}'
api "$T" POST sys/mounts/probe-kv '{"type":"kv","options":{"version":"2"}}'
row P2 setup "root KV mount probe-kv" "204" "HTTP $ST${ERR:+: $ERR}" "$(yes_if '[ "$ST" = 204 ]')"
for p in "" "$NS/"; do
  m=$([ -z "$p" ] && echo probe-kv || echo kv)
  api "$T" POST "${p}$m/data/canary" "$(jq -n --arg v "probe-demo-$EPOCH-a" '{data: {value: $v}}')"
done

# ── Q3: the GitHub App, root namespace and namespace ──────────────────────────
PEM_FP=$(openssl rsa -in "$PEM" -pubout -outform DER 2>/dev/null | openssl dgst -sha256 -binary | base64)
note "The PEM's public-key fingerprint (SHA-256, base64, as GitHub shows it) was computed locally; Vault's answer is compared below without printing either."
for p in "" "$NS/"; do
  where=$([ -z "$p" ] && echo root || echo namespace)
  api "$T" POST "${p}sys/sync/github-apps/$APP" "$(jq -n --arg id "$APP_ID" --rawfile k "$PEM" '{app_id: $id, private_key: $k}')"
  row P3 Q3 "register the GitHub App ($where)" "200" "HTTP $ST${ERR:+: $ERR}" "$(yes_if '[[ "$ST" =~ ^20[04]$ ]]')"
  api "$T" GET "${p}sys/sync/github-apps/$APP"
  VFP=$(jq -r '.data.fingerprint // empty' <<<"$BODY")
  row P3 Q3 "Vault's fingerprint equals the PEM's ($where)" "equal" "$([ -n "$VFP" ] && { [ "$VFP" = "$PEM_FP" ] || [ "$VFP" = "SHA256:$PEM_FP" ]; } && echo equal || echo "differs (Vault: ${VFP:0:12}...)")" \
    "$(yes_if '[ -n "$VFP" ] && { [ "$VFP" = "$PEM_FP" ] || [ "$VFP" = "SHA256:$PEM_FP" ]; }')"
  note "github-apps read ($where): keys $(jq -c '.data | keys' <<<"$BODY"), private_key shown as $(jq -r '.data.private_key // "absent"' <<<"$BODY" | cut -c1-5)."
done

# The gh destination: in the namespace first (the lab's preference, D9), then root.
GH_P=""
for p in "$NS/" ""; do
  where=$([ -z "$p" ] && echo root || echo namespace)
  api "$T" POST "${p}sys/sync/destinations/gh/$GH_DEST" "$(jq -n --arg a "$APP" --arg i "$INSTALL" --arg o "$OWNER" --arg r "$REPO" --arg t "${PREFIX}_{{ .SecretPath | uppercase }}_{{ .SecretKey | uppercase }}" \
    '{app_name: $a, installation_id: $i, repository_owner: $o, repository_name: $r, secrets_location: "repository", secret_name_template: $t}')"
  row P4 Q3 "create the gh destination with the app ($where)" "200" "HTTP $ST${ERR:+: $ERR}" "$(yes_if '[[ "$ST" =~ ^20[04]$ ]]')"
  if [[ "$ST" =~ ^20[04]$ ]] && [ -z "$GH_P" ]; then GH_P=$p; fi
  if [[ "$ST" =~ ^20[04]$ ]]; then
    api "$T" GET "${p}sys/sync/destinations/gh/$GH_DEST"
    note "gh destination read ($where): $(jq -c '.data | del(.connection_details.access_token) | {connection_details, options}' <<<"$BODY")."
  fi
done
GH_MOUNT=$([ -z "$GH_P" ] && echo probe-kv || echo kv)
api "$T" POST "${GH_P}sys/sync/destinations/gh/$GH_DEST/associations/set" "$(jq -n --arg m "$GH_MOUNT" '{mount: $m, secret_name: "canary"}')"
row P5 Q3 "associations/set (KV canary to GitHub)" "200" "HTTP $ST${ERR:+: $ERR}" "$(yes_if '[ "$ST" = 200 ]')"
t0=$(date +%s)
wait_status "$GH_P" gh "$GH_DEST" "$GH_MOUNT" canary 'SYNCED|FAILED|UNSYNC_FAILED' 40 || true
row P5 Q3 "Vault reports the GitHub sync" SYNCED "$STATUS after $(($(date +%s) - t0)) s" "$(yes_if '[ "$STATUS" = SYNCED ]')"
note "GitHub association status: $(jq -c '.data.associated_secrets // {} | to_entries | map(.value | {secret_name, sync_status, updated_at, error: (.error_message // null)})' <<<"$BODY")."
GH_NAME=$(gh_secrets | jq -r --arg p "$PREFIX" '[.[] | select(.name | startswith($p))] | first | .name // empty')
row P6 Q3 "gh secret list shows the synced secret (name only)" "PROBE_..._VALUE" "${GH_NAME:-absent}" "$(yes_if '[ -n "$GH_NAME" ]')"
before=$(gh_secrets | jq -r --arg n "$GH_NAME" '.[] | select(.name == $n) | .updatedAt')
sleep 2
api "$T" POST "${GH_P}$GH_MOUNT/data/canary" "$(jq -n --arg v "probe-demo-$EPOCH-b" '{data: {value: $v}}')"
t0=$(date +%s)
after=$before
for _ in $(seq 1 30); do
  after=$(gh_secrets | jq -r --arg n "$GH_NAME" '.[] | select(.name == $n) | .updatedAt')
  [ "$after" != "$before" ] && break
  sleep 2
done
row P7 Q3 "a new KV version updates the GitHub secret" "updatedAt changes" "$before -> $after ($(($(date +%s) - t0)) s)" "$(yes_if '[ -n "$after" ] && [ "$after" != "$before" ]')"
api "$T" POST "${GH_P}sys/sync/destinations/gh/$GH_DEST/associations/remove" "$(jq -n --arg m "$GH_MOUNT" '{mount: $m, secret_name: "canary"}')"
row P8 Q3 "associations/remove (GitHub)" "200" "HTTP $ST${ERR:+: $ERR}" "$(yes_if '[ "$ST" = 200 ]')"
gone=no
for _ in $(seq 1 30); do
  [ -z "$(gh_secrets | jq -r --arg n "$GH_NAME" '.[] | select(.name == $n) | .name')" ] && { gone=yes; break; }
  sleep 2
done
row P8 Q3 "the GitHub copy is deleted after remove" deleted "$([ "$gone" = yes ] && echo deleted || echo "still there")" "$gone"
api "$T" DELETE "${GH_P}sys/sync/github-apps/$APP"
row P9 Q3 "delete the app while a destination uses it" "refused" "HTTP $ST${ERR:+: $ERR}" "$(yes_if '[ "$ST" != 204 ]')"

# A real path (parcel/delivery-api) through a template: GitHub names allow only
# [A-Z0-9_]. Raw uppercase first, then with replace (the lab's candidate).
if [ -n "$GH_P" ]; then
  api "$T" POST "${GH_P}$GH_MOUNT/data/parcel/delivery-api" "$(jq -n --arg v "probe-demo-$EPOCH-path" '{data: {value: $v}}')"
  for kind in raw safe; do
    if [ "$kind" = raw ]; then tpl="${PREFIX}_{{ .SecretPath | uppercase }}_{{ .SecretKey | uppercase }}"
    else tpl="${PREFIX}_{{ .SecretPath | replace \"/\" \"_\" | replace \"-\" \"_\" | uppercase }}_{{ .SecretKey | uppercase }}"; fi
    api "$T" POST "${GH_P}sys/sync/destinations/gh/$GH_DEST-$kind" "$(jq -n --arg a "$APP" --arg i "$INSTALL" --arg o "$OWNER" --arg r "$REPO" --arg t "$tpl" \
      '{app_name: $a, installation_id: $i, repository_owner: $o, repository_name: $r, secret_name_template: $t}')"
    row P23 Q3 "gh destination, template on a path ($kind)" "200" "HTTP $ST${ERR:+: $ERR}" "$(yes_if '[[ "$ST" =~ ^20[04]$ ]]')"
    api "$T" POST "${GH_P}sys/sync/destinations/gh/$GH_DEST-$kind/associations/set" "$(jq -n --arg m "$GH_MOUNT" '{mount: $m, secret_name: "parcel/delivery-api"}')"
    note "associations/set parcel/delivery-api ($kind template): HTTP $ST ${ERR:-}."
    wait_status "$GH_P" gh "$GH_DEST-$kind" "$GH_MOUNT" parcel/delivery-api 'SYNCED|FAILED|UNSYNC_FAILED' 20 || true
    row P23 Q3 "sync status of parcel/delivery-api ($kind template)" "recorded" "$STATUS $(jq -r '[.data.associated_secrets // {} | to_entries[] | .value.error_message // empty] | first // ""' <<<"$BODY" | cut -c1-160)" yes
  done
  note "GitHub names after the path templates: $(gh_secrets | jq -c --arg p "$PREFIX" '[.[] | select(.name | startswith($p)) | .name]')."
fi

# ── Q4: aws-sm to LocalStack ──────────────────────────────────────────────────
AWS_P=""
NARROW=$(jq -n --arg ip "$LS_IP/32" --arg r "$REGION" '{access_key_id: "test", secret_access_key: "test", region: $r, allowed_ipv4_addresses: [$ip], allowed_ports: [4566]}')
for p in "$NS/" ""; do
  where=$([ -z "$p" ] && echo root || echo namespace)
  api "$T" POST "${p}sys/sync/destinations/aws-sm/$AWS_DEST" "$NARROW"
  row P10 Q4 "create aws-sm with allowed_ipv4_addresses $LS_IP/32 and port 4566 ($where)" "200" "HTTP $ST${ERR:+: $ERR}" "$(yes_if '[[ "$ST" =~ ^20[04]$ ]]')"
  if [[ "$ST" =~ ^20[04]$ ]] && [ -z "$AWS_P" ]; then AWS_P=$p; fi
done
AWS_MOUNT=$([ -z "$AWS_P" ] && echo probe-kv || echo kv)
api "$T" GET "${AWS_P}sys/sync/destinations/aws-sm/$AWS_DEST"
note "aws-sm destination read: $(jq -c '.data | del(.connection_details.secret_access_key) | {connection_details, options}' <<<"$BODY")."
api "$T" POST "${AWS_P}sys/sync/destinations/aws-sm/$AWS_DEST/associations/set" "$(jq -n --arg m "$AWS_MOUNT" '{mount: $m, secret_name: "canary"}')"
row P11 Q4 "associations/set (KV canary to LocalStack)" "200" "HTTP $ST${ERR:+: $ERR}" "$(yes_if '[ "$ST" = 200 ]')"
wait_status "$AWS_P" aws-sm "$AWS_DEST" "$AWS_MOUNT" canary 'SYNCED|FAILED|UNSYNC_FAILED' 30 || true
row P11 Q4 "Vault reports the LocalStack sync (narrow allowlist, SDK endpoint variable)" SYNCED "$STATUS" "$(yes_if '[ "$STATUS" = SYNCED ]')"
note "LocalStack association status (narrow): $(jq -c '.data.associated_secrets // {} | to_entries | map(.value | {sync_status, error: (.error_message // null)})' <<<"$BODY")."
if [ "$STATUS" != SYNCED ]; then
  # Recreate rather than PATCH (PATCH wants a merge-patch content type).
  api "$T" POST "${AWS_P}sys/sync/destinations/aws-sm/$AWS_DEST/associations/remove" "$(jq -n --arg m "$AWS_MOUNT" '{mount: $m, secret_name: "canary"}')"
  sleep 3
  api "$T" DELETE "${AWS_P}sys/sync/destinations/aws-sm/$AWS_DEST"
  api "$T" POST "${AWS_P}sys/sync/destinations/aws-sm/$AWS_DEST" "$(jq '. + {disable_strict_networking: true} | del(.allowed_ipv4_addresses, .allowed_ports)' <<<"$NARROW")"
  row P12 Q4 "fallback: recreate with disable_strict_networking true" "200" "HTTP $ST${ERR:+: $ERR}" "$(yes_if '[[ "$ST" =~ ^20[04]$ ]]')"
  api "$T" POST "${AWS_P}sys/sync/destinations/aws-sm/$AWS_DEST/associations/set" "$(jq -n --arg m "$AWS_MOUNT" '{mount: $m, secret_name: "canary"}')"
  wait_status "$AWS_P" aws-sm "$AWS_DEST" "$AWS_MOUNT" canary 'SYNCED|FAILED|UNSYNC_FAILED' 30 || true
  row P12 Q4 "Vault reports the LocalStack sync without strict networking" SYNCED "$STATUS" "$(yes_if '[ "$STATUS" = SYNCED ]')"
  note "LocalStack association status (no strict networking): $(jq -c '.data.associated_secrets // {} | to_entries | map(.value | {sync_status, error: (.error_message // null)})' <<<"$BODY")."
fi
aws_sm ListSecrets '{"MaxResults":100}'
LSN=$(jq -r '[.SecretList[]? | select(.Tags // [] | map(.Value) | any(test("probe")) ) | .Name] | first // empty' <<<"$ABODY")
[ -n "$LSN" ] || LSN=$(jq -r '[.SecretList[]?.Name | select(test("canary"))] | first // empty' <<<"$ABODY")
row P13 Q4 "the secret name Vault wrote in LocalStack" "recorded" "${LSN:-absent}" "$(yes_if '[ -n "$LSN" ]')"
note "LocalStack secret tags: $(jq -c --arg n "$LSN" '.SecretList[]? | select(.Name == $n) | .Tags' <<<"$ABODY")."
if [ -n "$LSN" ]; then
  aws_sm GetSecretValue "$(jq -n --arg n "$LSN" '{SecretId: $n}')"
  V1=$(jq -r '.SecretString // empty' <<<"$ABODY")
  row P13 Q4 "LocalStack holds the KV value (secret-path: JSON of all keys)" "fingerprint of {\"value\":...-a}" "$(fp "$V1")" "$(yes_if '[ "$(jq -r .value <<<"$V1" 2>/dev/null)" = "probe-demo-$EPOCH-a" ] || [ "$(jq -r .value <<<"$V1" 2>/dev/null)" = "probe-demo-$EPOCH-b" ]')"
  api "$T" POST "${AWS_P}$AWS_MOUNT/data/canary" "$(jq -n --arg v "probe-demo-$EPOCH-c" '{data: {value: $v}}')"
  ok=no
  for _ in $(seq 1 30); do
    aws_sm GetSecretValue "$(jq -n --arg n "$LSN" '{SecretId: $n}')"
    [ "$(jq -r '.SecretString // empty' <<<"$ABODY" | jq -r .value 2>/dev/null)" = "probe-demo-$EPOCH-c" ] && { ok=yes; break; }
    sleep 2
  done
  row P14 Q4 "a new KV version reaches LocalStack" "the new value's fingerprint" "$([ "$ok" = yes ] && fp "probe-demo-$EPOCH-c" || echo "not propagated")" "$ok"
  api "$T" POST "${AWS_P}sys/sync/destinations/aws-sm/$AWS_DEST/associations/remove" "$(jq -n --arg m "$AWS_MOUNT" '{mount: $m, secret_name: "canary"}')"
  gone=no
  for _ in $(seq 1 30); do
    aws_sm DescribeSecret "$(jq -n --arg n "$LSN" '{SecretId: $n}')"
    { [ "$AST" = 400 ] || jq -e '.DeletedDate' <<<"$ABODY" >/dev/null 2>&1; } && { gone=yes; break; }
    sleep 2
  done
  row P15 Q4 "remove deletes the LocalStack copy (or schedules it)" deleted "$([ "$gone" = yes ] && echo "gone: HTTP $AST $(jq -c '{DeletedDate}' <<<"$ABODY" 2>/dev/null)" || echo "still there")" "$gone"
fi

# ── Q5: Secrets Import from LocalStack ────────────────────────────────────────
for n in delivery-api smtp-relay; do
  # LocalStack requires ClientRequestToken (the AWS CLI adds one itself).
  aws_sm CreateSecret "$(jq -n --arg n "probe-$EPOCH/legacy/$n" --arg v "probe-demo-import-$n" --arg c "$(uuidgen)" '{Name: $n, ClientRequestToken: $c, SecretString: ({api_key: $v} | tojson), Tags: [{Key: "origin", Value: "probe"}]}')"
done
row P16 Q5 "seed two legacy secrets in LocalStack" "200" "HTTP $AST" "$(yes_if '[ "$AST" = 200 ]')"
podman exec "$(vault_container vault-1)" vault operator import -h >"$WORK/import-help" 2>&1 || true
row P17 Q5 "vault operator import exists in the 2.2.1 image" "usage" "$(head -1 "$WORK/import-help")" "$(yes_if 'grep -qi "usage" "$WORK/import-help"')"
api "$T" PUT sys/activation-flags/secrets-import/activate '{}'
row P18 Q5 "activate secrets-import" "200 or 204" "HTTP $ST${ERR:+: $ERR}" "$(yes_if '[[ "$ST" =~ ^20[04]$ ]]')"
api "$T" GET sys/activation-flags
note "Activation flags: $(jq -c '.data' <<<"$BODY")."
cat >"$WORK/import.hcl" <<HCL
source_aws {
  name               = "legacy"
  # Import's SSRF guard refuses private addresses; open LocalStack's /32 only.
  allowed_ipv4_cidrs = ["$LS_IP/32"]
}

destination_vault {
  name      = "lumen"
  address   = "https://vault-2:8200"
  namespace = "$NS"
  mount     = "kv"
}

mapping {
  name        = "legacy-to-parcel"
  source      = "legacy"
  destination = "lumen"
  filter      = "Secret.Name matches \"^probe-$EPOCH/legacy/.*\""
  transform "regexp" {
    from = "^probe-$EPOCH/legacy/(.*)$"
    to   = "imported/\$1"
  }
}
HCL
importer() { # <label> <args...>: vault operator import inside vault-1 (flags before plan|apply), LocalStack's synthetic credentials
  local label=$1
  shift
  podman exec -i "$(vault_container vault-1)" sh -c 'cat > /tmp/probe-import.hcl' <"$WORK/import.hcl"
  # credentials_profile reads the AWS config file, not credentials; the env pair is simpler.
  printf '%s' "$T" | podman exec -i -e AWS_ACCESS_KEY_ID=test -e AWS_SECRET_ACCESS_KEY=test -e AWS_REGION="$REGION" \
    "$(vault_container vault-1)" sh -c 'VAULT_TOKEN=$(cat) exec vault operator import -config=/tmp/probe-import.hcl "$@"' sh "$@" >"$WORK/import-$label" 2>&1
}
importer plan plan || true
row P19 Q5 "operator import plan (destination https://vault-2:8200, a private address)" "lists the two secrets" "$(tr '\n' ' ' <"$WORK/import-plan" | cut -c1-200)" \
  "$(yes_if 'grep -q "delivery-api" "$WORK/import-plan"')"
note "Import plan output: $(tr '\n' ' ' <"$WORK/import-plan" | cut -c1-900)."
importer apply -auto-approve apply || true
row P20 Q5 "operator import apply" "writes imported/*" "$(tail -3 "$WORK/import-apply" | tr '\n' ' ' | cut -c1-200)" "$(yes_if '! grep -qi "error" "$WORK/import-apply"')"
note "Import apply output: $(tr '\n' ' ' <"$WORK/import-apply" | cut -c1-900)."
api "$T" GET "$NS/kv/metadata/imported/delivery-api"
row P21 Q5 "the imported KV secret exists" "version 1" "HTTP $ST version $(jq -r '.data.current_version // "none"' <<<"$BODY")" "$(yes_if '[ "$ST" = 200 ]')"
note "Imported metadata: $(jq -c '.data | {current_version, custom_metadata, created_time}' <<<"$BODY")."
api "$T" GET "$NS/kv/data/imported/delivery-api"
# The seed is {"api_key": ...}: either Import parses it into KV keys, or it
# keeps the raw string under one key. Record which.
IKEYS=$(jq -c '.data.data | keys' <<<"$BODY")
if [ "$(jq -r '.data.data.api_key // empty' <<<"$BODY")" = probe-demo-import-delivery-api ]; then IMODE="parsed: api_key"
elif [ "$(jq -r '.data.data.value // empty' <<<"$BODY")" = '{"api_key":"probe-demo-import-delivery-api"}' ]; then IMODE="raw string under value"
else IMODE="neither"; fi
row P21 Q5 "how a JSON SecretString lands in KV" "parsed or raw, recorded" "keys $IKEYS, $IMODE" "$(yes_if '[ "$IMODE" != neither ]')"
importer apply -auto-approve apply || true
api "$T" GET "$NS/kv/metadata/imported/delivery-api"
row P22 Q5 "a second apply (re-import)" "recorded" "version $(jq -r '.data.current_version // "none"' <<<"$BODY")" yes
podman exec "$(vault_container vault-1)" rm -f /tmp/probe-import.hcl

took=$(($(date +%s) - started))
mkdir -p "$BUILD_DIR/probe"
{
  cat <<EOF
<!-- Generated by make probe. The table and the notes quote Vault, GitHub and
     LocalStack verbatim (long lines, JSON), so these rules are off here. -->
<!-- markdownlint-disable MD004 MD013 MD033 MD034 MD037 MD060 -->

# Capabilities (measured)

What Vault Enterprise 2.2.1 Secrets Sync and Secrets Import actually do with
the VaultSyncDemo GitHub App and LocalStack $(vsync_conf LOCALSTACK_IMAGE | sed 's/.*://'),
measured by \`make probe\` (\`scripts/probe.sh\`) on $(date -u +%Y-%m-%d) in
${took}s: $pass rows matched, $fail did not. Synthetic values only; values are
shown as fingerprints (first 8 hex of SHA-256), never in full.

| Case | Question | Call | Expected | Answer | Match |
| --- | --- | --- | --- | --- | --- |
EOF
  cat "$ROWS"
  printf '\n## Notes\n\n'
  cat "$NOTES"
} >"$OUT"
jq -n --argjson pass "$pass" --argjson fail "$fail" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{pass: $pass, fail: $fail, at: $at}' >"$BUILD_DIR/probe/results.json"
echo "probe: $pass passed, $fail failed in ${took}s; wrote docs/capabilities.md"
[ "$fail" -eq 0 ]
