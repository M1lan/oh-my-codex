#!/usr/bin/env node
// Guard: this repository is pnpm-only. npm/yarn/bun are not allowed and must
// never come back. Runs as the `preinstall` lifecycle script, so any attempt to
// install with another package manager fails fast before it can write a foreign
// lockfile or node_modules layout.
const agent = process.env.npm_config_user_agent ?? '';
const manager = agent.split('/')[0];

// Allow corepack/CI bootstrapping where the agent is occasionally unset, but
// reject every other concrete package manager outright.
if (manager && manager !== 'pnpm') {
  console.error(
    [
      '',
      '  ✘ This repository is pnpm-only. npm is not allowed.',
      `    Detected package manager: ${manager}`,
      '',
      '    Use pnpm instead:',
      '      pnpm install',
      '      pnpm run build',
      '',
      '    (Install pnpm via corepack: `corepack enable pnpm`)',
      '',
    ].join('\n'),
  );
  process.exit(1);
}
