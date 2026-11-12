// global-setup.ts: fail fast, with the make target that fixes it, when the
// stack is not up; a fresh stage; then sign in once as ines through the
// console's own form and keep the session for every journey.
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { chromium } from '@playwright/test';
import { labCaSpkiArg, served, stageReset } from './helpers/env';
import { signIn } from './helpers/auth';

const CORE = ['vaultsync-vault_s', 'vaultsync-vault_1', 'vaultsync-vault_2', 'vaultsync-vault_3', 'vaultsync-localstack', 'vaultsync-api', 'vaultsync-web'];
export const STORAGE = path.join(__dirname, '.auth/ines.json');

export default async function globalSetup(): Promise<void> {
  const running = execFileSync('podman', ['ps', '--filter', 'name=^vaultsync-', '--format', '{{.Names}}'], { encoding: 'utf8' }).split('\n');
  const down = CORE.filter((c) => !running.includes(c));
  if (down.length) throw new Error(`not running: ${down.join(', ')}: run "make up"`);
  // 200 only: with the API down, nginx itself answers 502.
  const h = await served('/api/healthz').catch(() => null);
  if (h?.status !== 200) throw new Error(`the API behind the console is not healthy (${h ? `HTTP ${h.status}` : 'no answer'}): run "make doctor"`);
  stageReset();
  const browser = await chromium.launch({ args: [labCaSpkiArg()] });
  const page = await browser.newPage();
  await signIn(page);
  await page.context().storageState({ path: STORAGE });
  await browser.close();
}
