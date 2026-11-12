# State

What was built, deferred and learned per build prompt. Read this first.

## Before prompt 01 (2026-11-12)

- Codex wrote prompts 00 to 08 and a generic `.claude/skills/SKILL.md`. The
  skill was in the wrong place (a skill needs its own folder) and named
  skills that do not exist (`/plan`, `/advisor`); it is now
  `.claude/skills/engineering-workflow/SKILL.md` with the installed skills'
  real names. The prompts were rewritten for the user's choices (pull =
  Secrets Import from LocalStack; the house pattern); Codex's are in
  `prompts/_codex/`.
- Checked in the official docs: the `aws-sm` destination has no custom
  endpoint parameter (LocalStack must be reached another way, the probe
  decides); `vault operator import` is alpha; LocalStack 2026.03.0 and later
  needs `LOCALSTACK_AUTH_TOKEN`.
- `.secrets/` and `.secrets/github/` were 0755 and the GitHub App PEM 0644;
  now 0700 and 0600.

## Prompt 01: Foundation (2026-11-12)

- Copied from `../vault_identity` git HEAD `b81dc78` (`git archive`),
  renamed `vid-`→`vaultsync-`, `VID_`→`VSYNC_`, namespace `lumen`, policies
  `vsync-*`, ports 196xx and 14101. Removed what this lab does not use: the
  PostgreSQL stack, the issuer and JWT code, the cases, the evidence store,
  the agents and their Terraform, the case pages; removed the scaffold's
  `main.tf`, `FOLDER_TREE.md`, `sanity_check.md`, `Containerfile`,
  `.dockerignore`.
- `config/story.json` (three synthetic legacy secrets, the synced and the
  rotating one) with `scripts/story-check.js` (5 unit tests).
- Network on a fixed subnet `10.89.240.0/24` (free on 2026-11-12), so
  LocalStack has a known address for the sync destination's allowlist.
- Tool versions: Terraform 1.14.2, ansible-core 2.21.3, Node 25.2.1 on the
  host, Podman 6.1.4, `lstk` 1.4.4, `gh` logged in as raymonepping.

## Prompt 02: Seal, cluster, the cloud stack (2026-11-12)

- Phases seal-up 2 s, seal-init 15 s, vault-seal 4 s, seal-tokens 5 s,
  vault-up 4 s, bootstrap 35 s. Restart 26 s. `make boundary`: 34 tool checks.
- Bootstrap policies for namespace `lumen` and Secrets Sync (root and
  namespaced `sys/sync/*` with `sudo`), the secrets-import activation flag,
  the 4h probe token for `probe-*` names.
- `compose/cloud`: `vaultsync-localstack` 2026.10.6 (arm64) at
  10.89.240.50, its auth token from `.env` by compose interpolation; the
  licence activated (freemium, `edition: pro` in the health answer). HTTPS
  with the lab certificate through `CUSTOM_SSL_CERT_PATH` (key, leaf, chain in
  one PEM from a one-shot `cert-init`): `curl --cacert` on localhost:14566
  verifies. Learned: the image has no `curl`; Podman splits a CMD-form
  healthcheck argument on spaces, so the healthcheck is shell form with the
  image's Python. LocalStack logs a harmless fallback because the cert
  volume is read-only.
- The Vault nodes carry `AWS_ENDPOINT_URL_SECRETS_MANAGER` and
  `AWS_CA_BUNDLE` from the start (they cannot be added without recreating
  the nodes); prompt 03 measures whether the SDK honours them.
  Measured in prompt 03: the first breaks STS, the second breaks the
  client; both replaced (see below).

## Prompt 03: The probe (2026-11-12)

- `make probe`: 35/35 in 11 s (`docs/capabilities.md`). First run 10/23;
  fixed in order: activate Secrets Sync, `ClientRequestToken` on
  `CreateSecret`, credentials in the environment (not `credentials_profile`),
  no `AWS_CA_BUNDLE` (use `SSL_CERT_DIR`), the global `AWS_ENDPOINT_URL`
  (STS), `allowed_ipv4_cidrs` in `source_aws`, flags before `apply`.
- The Vault nodes now carry `AWS_ENDPOINT_URL` and `SSL_CERT_DIR`; `make
  vault-up` recreated them in 8 s, unsealed.
- Decisions taken from the answers (`prompts/00_brief.md`): sync objects live
  in namespace `lumen` (D9), aws-sm with the /32 and port allowlist (D11),
  Import with env credentials and the /32 exemption (D12), legacy values are
  plain strings and an import runs only for paths KV does not hold (D19).

## Prompt 04: Platform, GitHub App, destinations, stage (2026-11-12)

- `make clean-slate CONFIRM=DELETE && make lab`: 142 s from nothing, gates
  green (idempotency changed=0 everywhere, drift empty, secret scan 14 known
  values, boundary 48 with 14 presenter rows). Phases: vault-platform 3 s,
  people 2 s, github-app 6 s, destinations 1 s, seed 3 s, stage 3 s,
  validate 4 s.
- Terraform `vault-platform`: audit (file + stdout), namespace `lumen`, KV v2
  `kv`, userpass, one policy `vsync-presenter`. D13 changed: no console
  token. Ines's own session token runs every act, so the audit log names
  her; she writes values and never reads one, and moves only the two
  destinations' associations.
- Ansible: `people` (ines), `github-app` (activation flags, the app with a
  fingerprint check, `lumen-github` with `LUMEN_{{ .SecretPath | uppercase
  }}_{{ .SecretKey | uppercase }}`), `destinations` (`lumen-localstack`,
  /32 and port 4566, template `vault/lumen/{{ .SecretPath }}`), `seed` (three
  legacy secrets, `ClientRequestToken` from `to_uuid`), `stage`
  (`.build/stage/stage.json`), `stage-reset`, `validate`. A destination that
  differs from its declaration is not rewritten (it may carry associations);
  the run stops and says how to recreate it.
- Learned: Ansible's `uri` parses only `application/json`; LocalStack answers
  `application/x-amz-json-1.1`, so the roles read `content | from_json`.
- `make github-forget-key` without `CONFIRM=yes` refuses; a missing key
  stops `github-app` with the instruction (tested against an empty folder,
  the real key never moved). `make clean-slate` removes the associations
  first, so GitHub keeps no orphaned `LUMEN_` secret.
- `make github-evidence`: 0 `LUMEN_` secrets (nothing synced yet).

## Prompt 05: API (2026-11-12)

- Node 24, no dependencies: `lib/vault.js` (no console token; every call
  names the presenter's token and an `X-Correlation-Id`), `lib/session.js`
  (ines), `lib/localstack.js` (fetch, fingerprints only), `lib/importer.js`
  (the import config from `config/story.json`, `vault operator import` as a
  child process: argv list, token in the child's environment, config 0600 in
  tmpfs, removed after), `lib/story.js` (the four acts, the allowlist, one
  step at a time, a bounded event list, GitHub evidence and staleness),
  `server.js`. `npm test`: 25/25.
- The API image is the Vault Enterprise image plus Node 24 (two C++ libs
  copied from node:24-alpine): about 110 MB of new layers instead of a
  555 MB binary on the Node image. `make stage-reset` clears the event list
  with `podman kill --signal USR2`.
- Measured through the API as Ines: the plan lists the three legacy secrets;
  apply wrote version 1 of each with Import's labels plus LocalStack's tags
  as custom metadata; the API added `value_fp` (equal to the legacy value's
  fingerprint); a second apply is refused (409) before it can write version 2.
- Learned: (1) Import writes metadata first, so the caller needs `create` on
  `kv/metadata/...`; (2) **the CLI exits 0 when every write was refused**:
  the API reads its "Secrets not imported" list, so a refused import is
  never reported as a success (unit test); (3) **`associations/set` needs
  read on the secret** ("permission denied to read the content of the
  secret"): Ines may read exactly `config/story.json` `sync.secret` (a
  Terraform template variable), no other secret; boundary 50.

## Prompt 06: Console (2026-11-12)

- React 19 + Vite on vault_identity's glass shell: Overview, Bring home, Send
  out, Change once, Proof. The two-way map (legacy store into Vault, Vault
  out to GitHub Actions and the AWS copy, each arrow with Vault's own state
  and time) sits in every page's single ink hero, full on Overview, compact
  elsewhere, stacked with downward arrows on a phone.
- `make test-ui`: 22 passed in 51 s (the four acts from the real buttons
  against GitHub and LocalStack, axe WCAG 2.1 AA zero violations on five
  pages at 1440x900 and 390x844 plus the sign-in form, TLS 1.3, CSP, no
  legacy or rotated value on any page or in any bundle). `make screenshots`:
  ten images in `docs/screenshots/`, each looked at.
- Fixed from the screenshots and axe: the indigo `manual` pill is under AA on
  glass (a neutral `none` pill instead); JetBrains Mono ligatures turned the
  CLI's `->` into an arrow (ligatures off in output); the Import arrow showed
  the rotation's time (KV `created_time` now); "secret(s)"; card spacing in
  the two-column grid.
- `make rehearsal` (prompt 07's, built here because the harness blocks a
  direct sign-in from the session): 47 passed in 27 s. GitHub showed the
  rotation within about 1 s; the stale rule compares whole seconds (gh and
  GitHub give seconds, Vault fractions), unit-tested.
- Playwright's request fixture trusts the lab CA through
  `NODE_EXTRA_CA_CERTS` in the make target, never `ignoreHTTPSErrors`.

## Prompt 07: Rehearsal and daily operations (2026-11-12)

- `make rehearsal`: 47/0 in 29 s. `make verify`: 77/0 in 142 s (podman,
  vault, units, platform, stage, cloud, app, console, boundary 50, drift,
  idempotency, secret scan, rehearsal).
- `make down` 10 s, `make up RUNTIME=podman` 55 s (LocalStack is most of it).
- Learned: (1) **LocalStack keeps nothing across a restart on the free
  licence**: with `PERSISTENCE=1` its state directory stayed empty. The
  setting is gone; `make up` re-seeds the legacy store when LocalStack starts
  fresh, and the destinations phase removes any association whose AWS copy
  LocalStack lost (tested: a shown state survives a down and up with its
  imported secrets and the GitHub copy; the AWS association is removed and
  the presenter pushes again). (2) A file replaced by rename on the host
  answered ENOENT to every second read inside a container (the VM's shared
  folder): `make github-evidence` writes in place, the API retries a short
  read once. (3) The Vault Enterprise image declares two volumes; the API
  covers them with tmpfs, or every recreate leaves two anonymous volumes (two
  removed). (4) Playwright's teardown resets the stage unless `KEEP_STAGE=1`.
- `make backup` takes LocalStack's state as a tarball next to the Raft
  snapshots; doctor checks the activation flags, the app, both destinations,
  LocalStack and the legacy store, the GitHub key, `gh auth`.

## Prompt 08: The Lab Index (2026-11-12)

- Refresh: vault_sync is eligible, prefix `vaultsync-` (source `lab`), the
  README's title, `running` with 7 containers.
- Stop through the dashboard (its `data-lab` card, `stop`, `confirm-stop`):
  10 s, every `vaultsync-` container stopped, every volume kept, no other
  lab touched. Start: 54 s (`make up RUNTIME=podman`, exit 0), then `make
  verify` 77/0. LocalStack does not keep its state (free licence): Start
  re-seeded the legacy store and reconciled the AWS destination, by design.
- Screenshots: `docs/screenshots/lab-index-{running,stopped,started}.png`.
- The card shows no links yet: the Lab Index takes them from the README
  (prompt 09).

## Prompt 09: Docs, public readiness, final runs (2026-11-12)

- Rewritten for this lab: README (title and first paragraph for the Lab
  Index, the four acts, prerequisites, checks, ports), architecture,
  operations, security model, ownership, DESIGN.md, CHANGELOG, CONTRIBUTING,
  CI (story-check, no npm install for the dependency-free API), the web
  page's title. markdownlint clean; no em dash in a public file.
- Public readiness: every private path ignored (`.ansible/` added); no
  private path, e-mail or secret-shaped string in the files to commit;
  gitleaks on exactly those files: no leaks (the story-check fixture lost its
  Stripe-shaped string).
- Final runs: from a stopped stack `make down` 10 s, `make up` 56 s, `make
  verify` 77/0, `make test-ui` 22/0. From nothing `make clean-slate` then
  `make lab` 156 s and `make verify` 77/0 in 136 s.
- Open observation: once, the first `make verify` straight after a fresh
  `make up` failed drift and idempotency; five reruns (slices and full) did
  not reproduce it. `verify` now prints a failing check's last lines, so a
  repeat names its phase.

## Prompt 99, round 1 (2026-11-12, after 88b14a6)

Reviews: ponytail-audit (1 to 10), ponytail-review (11 to 14),
backend-design audit of `api/` (15 to 17), security discipline (18 to 21).
Every finding fixed:

1. `make license-features` checked Agentic IAM: now Namespaces, Secrets
   Sync, Secrets Import.
2. A partly failed import never labelled the secrets that landed: it labels
   exactly the paths now in KV (a label on a missing path would create it);
   unit test.
3. to 6. Dead code removed: four probe helpers, `vault_list_json`, five
   unused CSS rule groups, `Mono`, `useHashParam`, StepButton's `busy`, the
   `make api-test` alias.
7. `make github-installation` (scripts/github-installation.sh) runs the
   installation lookup; README points at it.
8. The evidence retry has a test (a half-written file read again).
9. The Vault nodes' AWS comment: one accurate comment instead of two.
10. `/api/sources` reads GitHub's associations itself instead of the full
    sync view again.
11. A rotation whose fingerprint label is refused is no longer reported as
    done; unit test.
12. The AWS reconcile derives the copy prefix from the template and asserts
    its shape (rendered: `vault/lumen/`).
13. `make backup` no longer tars LocalStack's always-empty state.
14. doctor counts the story's own legacy names.
15. nginx waits 120 s for the API (the import may take 90 s).
16. A refused revoke at sign-out is logged (never the token); unit test.
17. A 5xx request log line carries its reason.
18. Seed and validate loop over names and labels only: a failing item can no
    longer print a value (create path proven: one legacy secret deleted,
    re-created, validate green).
19. The security model states LocalStack's open loopback port as a limit.
20. Not a code to-do: `make github-installation` shows the GitHub App still
    holds agent, Codespaces and Dependabot secrets write; the user narrows it
    in GitHub (the lab never changes app settings).
21. `make up` said "kept" when compose had recreated the app with new
    images; it compares container ids now.

Results: API tests 29/29, lint clean, `make verify` 77/0, `make test-ui`
22/0, stage reset.
