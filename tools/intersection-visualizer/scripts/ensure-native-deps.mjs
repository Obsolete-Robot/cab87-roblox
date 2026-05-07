import { spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const projectDir = resolve(dirname(fileURLToPath(import.meta.url)), '..');

function isMissingRollupDependency(error) {
  const text = `${error?.message ?? ''}\n${error?.stack ?? ''}`;
  return text.includes("Cannot find module 'rollup'")
    || text.includes('@rollup/rollup-')
    || text.includes('rollup/dist/native');
}

function assertRollupLoads() {
  try {
    require('rollup');
    return true;
  } catch (error) {
    if (!isMissingRollupDependency(error)) {
      throw error;
    }
    return false;
  }
}

if (!assertRollupLoads()) {
  console.warn('[cab87] Rollup native optional dependency is missing; repairing node_modules with npm install...');
  const result = spawnSync('npm', ['install', '--include=optional'], {
    cwd: projectDir,
    stdio: 'inherit',
    shell: process.platform === 'win32',
  });

  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }

  if (!assertRollupLoads()) {
    console.error('[cab87] Rollup still cannot load after npm install. Remove node_modules and run npm install again.');
    process.exit(1);
  }
}
