#!/usr/bin/env node
// scripts/story-check.js: validate config/story.json (the legacy secrets, the
// KV names they land on, what syncs and what rotates) and print a digest.
// Standard library only. Exit 1 on any error.
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';

const AWS_NAME = /^[A-Za-z0-9/_+=.@-]{1,512}$/;
const KV_NAME = /^[a-z0-9-]+(\/[a-z0-9-]+)+$/;
const USER = /^[a-z][a-z0-9-]{1,30}$/;
// Values are synthetic and say so: gitleaks blocks real-looking secrets, and
// the GitHub repository is public (its secret names and times are visible).
const SYNTHETIC = /demo/;

export function check(doc) {
  const errors = [];
  const err = (m) => errors.push(m);
  if (!USER.test(doc.presenter?.user ?? '')) err('presenter.user must be a short lowercase name');
  const kvNames = new Set();
  for (const [i, l] of (doc.legacy ?? []).entries()) {
    const at = `legacy[${i}]`;
    if (!AWS_NAME.test(l.aws_name ?? '')) err(`${at}: aws_name is not a valid AWS Secrets Manager name`);
    if (!KV_NAME.test(l.kv_name ?? '')) err(`${at}: kv_name must be a lowercase path like parcel/name`);
    if (kvNames.has(l.kv_name)) err(`${at}: kv_name ${l.kv_name} is used twice`);
    kvNames.add(l.kv_name);
    // A plain string: Secrets Import keeps a SecretString raw under the KV key
    // "value" (probe P21), so JSON here would land as JSON inside one key.
    if (typeof l.value !== 'string' || !SYNTHETIC.test(l.value)) err(`${at}: value must be a string with "demo" in it (synthetic)`);
    if (!l.labels?.owner) err(`${at}: labels.owner is missing`);
  }
  if (!(doc.legacy ?? []).length) err('no legacy secrets');
  if (!kvNames.has(doc.sync?.secret)) err('sync.secret must be one of the imported kv_names');
  for (const d of doc.sync?.destinations ?? []) if (!['github', 'localstack'].includes(d)) err(`sync: unknown destination ${d}`);
  if (!kvNames.has(doc.rotate)) err('rotate must be one of the imported kv_names');
  return errors;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const raw = readFileSync(new URL('../config/story.json', import.meta.url));
  const errors = check(JSON.parse(raw));
  if (errors.length) {
    for (const e of errors) console.error(`story-check: ${e}`);
    process.exit(1);
  }
  const doc = JSON.parse(raw);
  const digest = createHash('sha256').update(raw).digest('hex').slice(0, 8);
  console.log(`story-check: ${doc.legacy.length} legacy secrets, syncs ${doc.sync.secret} to ${doc.sync.destinations.join(' and ')}, digest ${digest}`);
}
