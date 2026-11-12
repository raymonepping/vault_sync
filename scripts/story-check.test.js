import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { check } from './story-check.js';

const doc = () => JSON.parse(readFileSync(new URL('../config/story.json', import.meta.url)));

test('the shipped story is valid', () => {
  assert.deepEqual(check(doc()), []);
});

test('a real-looking value is refused (the GitHub repository is public)', () => {
  const d = doc();
  d.legacy[0].value = 'prod-delivery-key-7f3a9c'; // no "demo": not marked synthetic
  assert.match(check(d).join(), /synthetic/);
});

test('an AWS name with a space is refused', () => {
  const d = doc();
  d.legacy[1].aws_name = 'lumen legacy/printer';
  assert.match(check(d).join(), /not a valid AWS/);
});

test('the synced secret must be one that was imported', () => {
  const d = doc();
  d.sync.secret = 'parcel/unknown';
  assert.match(check(d).join(), /sync.secret/);
});

test('two legacy secrets cannot land on one KV path', () => {
  const d = doc();
  d.legacy[1].kv_name = d.legacy[0].kv_name;
  assert.match(check(d).join(), /used twice/);
});
