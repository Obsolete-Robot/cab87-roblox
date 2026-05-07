import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const projectDir = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const packageJsonPath = resolve(projectDir, 'package.json');

function packagePath(packageName) {
  return resolve(projectDir, 'node_modules', ...packageName.split('/'));
}

function getDeclaredDependencies() {
  const packageJson = JSON.parse(readFileSync(packageJsonPath, 'utf8'));
  return Array.from(new Set([
    ...Object.keys(packageJson.dependencies ?? {}),
    ...Object.keys(packageJson.devDependencies ?? {}),
  ])).sort();
}

function getMissingDeclaredDependencies() {
  return getDeclaredDependencies().filter((packageName) => !existsSync(packagePath(packageName)));
}

function runNpmInstall(reason) {
  console.warn(`[cab87] ${reason}; repairing node_modules with npm install...`);
  const result = spawnSync('npm', ['install', '--include=optional'], {
    cwd: projectDir,
    stdio: 'inherit',
    shell: process.platform === 'win32',
  });

  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

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

const missingDependencies = getMissingDeclaredDependencies();
if (missingDependencies.length > 0) {
  runNpmInstall(`Missing npm dependencies (${missingDependencies.join(', ')})`);

  const stillMissingDependencies = getMissingDeclaredDependencies();
  if (stillMissingDependencies.length > 0) {
    console.error(`[cab87] Dependencies are still missing after npm install: ${stillMissingDependencies.join(', ')}`);
    process.exit(1);
  }
}

if (!assertRollupLoads()) {
  runNpmInstall('Rollup native optional dependency is missing');

  if (!assertRollupLoads()) {
    console.error('[cab87] Rollup still cannot load after npm install. Remove node_modules and run npm install again.');
    process.exit(1);
  }
}
