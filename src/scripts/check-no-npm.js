#!/usr/bin/env node
// Guard: this repository is pnpm-only and npm must never come back.
//
// `only-pnpm.js` blocks foreign package managers at install time. This guard
// is the static counterpart: it fails CI if an npm/npx command invocation
// reappears in any package-manager surface (package.json scripts, CI
// workflows, Dockerfiles, shell scripts, build helpers).
//
// Scope is deliberately limited to surfaces where the project itself *runs* a
// package manager. It does NOT scan prose docs, historical changelogs, or the
// ecosystem-detection regexes in src/** (where "npm" is a registry/ecosystem
// proper noun the runtime must keep recognising in third-party input).
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

const SURFACE = [
  /(^|\/)package\.json$/,
  /^\.github\/workflows\/.*\.ya?ml$/,
  /\.sh$/,
  /(^|\/)Dockerfile[^/]*$/,
  /\.(mjs|cjs)$/,
  /^src\/scripts\/prepare-build\.js$/,
];

// Files exempt from the scan (they mention npm on purpose to forbid it).
const EXEMPT_FILES = new Set(['src/scripts/only-pnpm.js', 'src/scripts/check-no-npm.js']);

// Per-line allowlist: registry URLs and the npm_config_* env namespace are not
// npm command invocations (pnpm publishes to the same registry and sets the
// same env vars).
const LINE_ALLOW = [/npmjs\.com/, /img\.shields\.io\/npm/, /npm_config/, /package-ecosystem/];

const VIOLATION =
  /\bnpm (?:install|ci|run|test|publish|pack|view|exec|link|audit|add|update|version|init|config|cache|dedupe|prune|rebuild|i)\b|\bnpx\b|cache:\s*['"]?npm\b/;

function trackedFiles() {
  const out = execFileSync('git', ['ls-files'], { encoding: 'utf-8' });
  return out.split('\n').filter(Boolean);
}

const violations = [];
for (const file of trackedFiles()) {
  if (EXEMPT_FILES.has(file)) continue;
  if (!SURFACE.some((re) => re.test(file))) continue;
  let content;
  try {
    content = readFileSync(file, 'utf-8');
  } catch {
    continue;
  }
  const lines = content.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (LINE_ALLOW.some((re) => re.test(line))) continue;
    if (VIOLATION.test(line)) {
      violations.push(`${file}:${i + 1}: ${line.trim()}`);
    }
  }
}

if (violations.length > 0) {
  console.error('\n  ✘ npm/npx command usage detected — this repository is pnpm-only:\n');
  for (const v of violations) console.error(`    ${v}`);
  console.error('\n  Replace with the pnpm equivalent (pnpm install / pnpm run / pnpm dlx / pnpm add -g).\n');
  process.exit(1);
}

console.log('check:no-npm — no npm/npx command usage in package-manager surfaces.');
