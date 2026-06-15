#!/usr/bin/env node
import { existsSync, rmSync } from 'node:fs';
import { delimiter, join } from 'node:path';
import { spawnSync } from 'node:child_process';

const requiredDistFiles = [
  join(process.cwd(), 'dist', 'cli', 'omx.js'),
  join(process.cwd(), 'dist', 'scripts', 'postinstall.js'),
];

if (requiredDistFiles.every((file) => existsSync(file))) {
  process.exit(0);
}

const pnpmBin = process.platform === 'win32' ? 'pnpm.cmd' : 'pnpm';
const tscBin = process.platform === 'win32'
  ? join(process.cwd(), 'node_modules', '.bin', 'tsc.cmd')
  : join(process.cwd(), 'node_modules', '.bin', 'tsc');
const nodeModulesDir = join(process.cwd(), 'node_modules');

function runPnpm(args, env = process.env) {
  return spawnSync(pnpmBin, args, {
    cwd: process.cwd(),
    stdio: process.env.npm_config_json === 'true' ? ['inherit', 'ignore', 'inherit'] : 'inherit',
    env,
  });
}

function exitOnFailure(result, label) {
  if (result.error) {
    console.error(`omx prepare: failed to launch ${label}: ${result.error.message}`);
    process.exit(1);
  }

  if (result.status !== 0) {
    process.exit(typeof result.status === 'number' ? result.status : 1);
  }
}

let shouldCleanupBootstrappedDependencies = false;

if (!existsSync(tscBin)) {
  const hadNodeModules = existsSync(nodeModulesDir);
  const installResult = runPnpm(
    [
      'install',
      '--config.global=false',
      '--prod=false',
      '--include=dev',
      '--ignore-scripts',
      '--reporter=silent',
    ],
    {
      ...process.env,
      npm_config_global: 'false',
      npm_config_location: 'project',
    },
  );
  exitOnFailure(installResult, 'pnpm dependency bootstrap');
  shouldCleanupBootstrappedDependencies = !hadNodeModules;
}

const pathWithLocalBins = [
  join(process.cwd(), 'node_modules', '.bin'),
  process.env.PATH ?? '',
].filter(Boolean).join(delimiter);

const buildResult = spawnSync(pnpmBin, ['run', 'build'], {
  cwd: process.cwd(),
  stdio: process.env.npm_config_json === 'true' ? ['inherit', 'ignore', 'inherit'] : 'inherit',
  env: { ...process.env, PATH: pathWithLocalBins },
});
exitOnFailure(buildResult, 'pnpm build');

if (shouldCleanupBootstrappedDependencies) {
  try {
    rmSync(nodeModulesDir, { recursive: true, force: true });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.warn(`[omx:prepare] Warning: could not remove bootstrapped node_modules: ${message}`);
  }
}
