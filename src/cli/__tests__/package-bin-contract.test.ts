import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readdirSync, readFileSync, rmSync } from 'node:fs';
import { arch, platform, tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { getInstallableNativeAgentNames } from '../../agents/policy.js';
import { getSetupInstallableSkillNames } from '../../catalog/installable.js';
import { readCatalogManifest } from '../../catalog/reader.js';
import { OMX_FIRST_PARTY_MCP_PLUGIN_TARGETS } from '../../config/omx-first-party-mcp.js';

type PackageJson = {
  files?: string[];
  bin?: string | Record<string, string>;
  scripts?: Record<string, string>;
};

describe('package bin contract', () => {
  it('declares omx with an explicit relative bin path and avoids packaging platform-specific native binaries', () => {
    const packageJsonPath = join(process.cwd(), 'package.json');
    const pkg = JSON.parse(readFileSync(packageJsonPath, 'utf-8')) as PackageJson;
    const binaryName = platform() === 'win32' ? 'omx-sparkshell.exe' : 'omx-sparkshell';
    const packagedSparkShellPath = join(
      process.cwd(),
      'bin',
      'native',
      `${platform()}-${arch()}`,
      binaryName,
    );

    assert.deepEqual(pkg.bin, { omx: 'dist/cli/omx.js' });
    assert.equal(pkg.scripts?.['build:explore'], 'cargo build -p omx-explore-harness');
    assert.equal(pkg.scripts?.['build:explore:release'], 'node dist/scripts/build-explore-harness.js');
    assert.equal(pkg.scripts?.['build:full'], 'pnpm run build && pnpm run build:explore:release && pnpm run build:sparkshell && pnpm run build:api');
    assert.equal(pkg.scripts?.['build:api'], 'node dist/scripts/build-api.js');
    assert.equal(pkg.scripts?.['clean:native-package-assets'], 'node dist/scripts/cleanup-explore-harness.js');
    assert.equal(pkg.scripts?.['sync:plugin'], 'node dist/scripts/sync-plugin-mirror.js');
    assert.equal(pkg.scripts?.['sync:plugin:check'], 'node dist/scripts/sync-plugin-mirror.js --check');
    assert.equal(pkg.scripts?.['verify:plugin-bundle'], 'node dist/scripts/sync-plugin-mirror.js --check');
    assert.equal(pkg.scripts?.['verify:native-agents'], 'node dist/scripts/verify-native-agents.js');
    assert.equal(pkg.scripts?.prepack, 'pnpm run build && pnpm run verify:native-agents && pnpm run sync:plugin && pnpm run verify:plugin-bundle && pnpm run clean:native-package-assets');
    assert.equal(pkg.scripts?.prepare, 'node src/scripts/prepare-build.js');
    assert.match(pkg.scripts?.postinstall ?? '', /dist\/scripts\/postinstall\.js/);
    assert.match(pkg.scripts?.postinstall ?? '', /existsSync/);
    assert.equal(pkg.scripts?.postpack, 'pnpm run clean:native-package-assets');
    assert.equal(pkg.scripts?.['test:explore'], 'cargo test -p omx-explore-harness && node --test dist/cli/__tests__/explore.test.js dist/hooks/__tests__/explore-routing.test.js dist/hooks/__tests__/explore-sparkshell-guidance-contract.test.js');
    assert.equal(pkg.scripts?.['test:team:cross-rebase-smoke:compiled'], 'node dist/scripts/run-test-files.js dist/team/__tests__/cross-rebase-smoke.test.js');
    assert.equal(pkg.scripts?.['test:node'], 'node dist/scripts/run-test-files.js dist');
    assert.equal(pkg.scripts?.test, 'pnpm run build && pnpm run verify:native-agents && pnpm run verify:plugin-bundle && pnpm run test:node && node dist/scripts/generate-catalog-docs.js --check');
    assert.equal(pkg.scripts?.['test:ci:compiled'], 'pnpm run verify:native-agents && pnpm run verify:plugin-bundle && pnpm run test:node && node dist/scripts/generate-catalog-docs.js --check');
    assert.equal(
      pkg.scripts?.['coverage:team-critical'],
      'pnpm run build && pnpm run coverage:team-critical:compiled',
    );
    assert.equal(
      pkg.scripts?.['coverage:team-critical:compiled'],
      "c8 --all --src dist/team --src dist/state --include 'dist/team/**/*.js' --include 'dist/state/**/*.js' --exclude '**/__tests__/**' --reporter=text-summary --reporter=lcov --reporter=json-summary --report-dir coverage/team --check-coverage --lines=78 --functions=90 --branches=70 --statements=78 node dist/scripts/run-test-files.js dist/team/__tests__ dist/state/__tests__",
    );
    assert.equal(
      pkg.scripts?.['coverage:ts:full'],
      'pnpm run build && pnpm run coverage:ts:full:compiled',
    );
    assert.equal(
      pkg.scripts?.['coverage:ts:full:compiled'],
      "c8 --all --src dist --exclude '**/__tests__/**' --exclude 'dist/bin/**' --exclude 'dist/**/*.d.ts' --reporter=text-summary --reporter=lcov --reporter=json-summary --report-dir coverage/ts-full node dist/scripts/run-test-files.js dist",
    );
    assert.equal(
      pkg.scripts?.['test:ralph-persistence:compiled'],
      'node dist/scripts/run-test-files.js dist/cli/__tests__/session-scoped-runtime.test.js dist/mcp/__tests__/trace-server.test.js dist/hud/__tests__/state.test.js dist/mcp/__tests__/state-server-ralph-phase.test.js dist/ralph/__tests__/persistence.test.js dist/verification/__tests__/ralph-persistence-gate.test.js',
    );
    assert.equal(
      pkg.scripts?.['test:plugin-boundaries:compiled'],
      'node dist/scripts/run-test-files.js dist/cli/__tests__/codex-plugin-layout.test.js dist/cli/__tests__/package-bin-contract.test.js dist/cli/__tests__/setup-hooks-shared-ownership.test.js dist/catalog/__tests__/plugin-bundle-ssot.test.js',
    );
    assert.equal(pkg.scripts?.['test:compat:node'], 'pnpm run build && node dist/scripts/run-test-files.js dist/compat/__tests__');

    for (const scriptName of ['test:node', 'test:ci:compiled', 'coverage:team-critical', 'coverage:team-critical:compiled', 'coverage:ts:full', 'coverage:ts:full:compiled', 'test:team:cross-rebase-smoke:compiled', 'test:team:worker-runtime-identity:compiled', 'test:recent-bug-regressions:compiled', 'test:ralph-persistence:compiled', 'test:plugin-boundaries:compiled', 'test:explicit-terminal-contract:compiled', 'test:compat:node'] as const) {
      const script: string | undefined = pkg.scripts?.[scriptName];
      assert.ok(script, `expected ${scriptName} to exist`);
      assert.equal(script.includes('$(find '), false, `${scriptName} should not rely on POSIX command substitution`);
      assert.equal(script.includes('*.test.js'), false, `${scriptName} should not rely on shell glob expansion`);
    }

    assert.equal(pkg.files?.includes('dist/'), true, 'expected package files allowlist to include dist/');
    assert.equal(pkg.files?.includes('bin/'), false, 'did not expect broad bin/ allowlist in package files');
    assert.equal(pkg.files?.includes('agents/'), false, 'native agent TOMLs are setup output, not package input');
    assert.ok(pkg.files?.includes('Cargo.toml'));
    assert.ok(pkg.files?.includes('Cargo.lock'));
    assert.ok(pkg.files?.includes('crates/'));
    assert.ok(pkg.files?.includes('plugins/'));
    assert.ok(pkg.files?.includes('.agents/plugins/marketplace.json'));

    const binPath = join(process.cwd(), 'dist', 'cli', 'omx.js');
    const compiledCliPath = join(process.cwd(), 'dist', 'cli', 'index.js');

    const prepareBuildSource = readFileSync(join(process.cwd(), 'src', 'scripts', 'prepare-build.js'), 'utf-8');
    assert.match(prepareBuildSource, /dist.*cli.*omx\.js/s);
    assert.match(prepareBuildSource, /dist.*scripts.*postinstall\.js/s);
    assert.match(prepareBuildSource, /pnpm.*run.*build/s);
    assert.match(prepareBuildSource, /--config\.global=false/s);
    assert.match(prepareBuildSource, /--prod=false/s);
    assert.match(prepareBuildSource, /npm_config_global.*false/s);
    assert.match(prepareBuildSource, /npm_config_location.*project/s);
    assert.match(prepareBuildSource, /shouldCleanupBootstrappedDependencies/s);
    assert.match(prepareBuildSource, /hadNodeModules/s);
    assert.match(prepareBuildSource, /nodeModulesDir/s);
    assert.match(prepareBuildSource, /rmSync.*node_modules/s);
    assert.match(prepareBuildSource, /--reporter=silent/s);
    assert.match(prepareBuildSource, /--ignore-scripts/s);

    const binSource = readFileSync(binPath, 'utf-8');
    const compiledCliSource = readFileSync(compiledCliPath, 'utf-8');
    assert.match(binSource, /^#!\/usr\/bin\/env node/);
    const mcpInitialize = JSON.stringify({
      jsonrpc: '2.0',
      id: 1,
      method: 'initialize',
      params: {
        protocolVersion: '2024-11-05',
        capabilities: {},
        clientInfo: { name: 'package-bin-contract', version: '0' },
      },
    }) + '\n';
    for (const target of OMX_FIRST_PARTY_MCP_PLUGIN_TARGETS) {
      const mcpServe = spawnSync(
        process.execPath,
        [binPath, 'mcp-serve', target],
        {
          cwd: process.cwd(),
          encoding: 'utf-8',
          input: mcpInitialize,
          timeout: 5_000,
        },
      );
      assert.equal(
        mcpServe.status,
        0,
        `${target} stderr=${mcpServe.stderr} stdout=${mcpServe.stdout}`,
      );
      assert.notEqual(
        mcpServe.stdout.trim(),
        '',
        `omx bin wrapper must keep mcp-serve ${target} alive long enough to complete stdio initialization`,
      );
      const mcpResponse = JSON.parse(mcpServe.stdout) as {
        result?: { serverInfo?: { name?: string; version?: string } };
      };
      assert.match(
        mcpResponse.result?.serverInfo?.name ?? '',
        /^omx-/,
        `${target} initialize response should include serverInfo`,
      );
    }
    assert.match(compiledCliSource, /omx update\s+Install the stable channel now, then refresh setup/);
    assert.match(compiledCliSource, /omx update --stable\s+Install\/rollback to the stable release \(oh-my-codex@latest\), then refresh setup/);
    assert.match(compiledCliSource, /omx update --dev\s+Install the upstream dev branch, then refresh setup/);
    assert.match(compiledCliSource, /case "update"/);

    rmSync(packagedSparkShellPath, { force: true });

    const packDir = mkdtempSync(join(tmpdir(), 'omx-pnpm-pack-'));
    let packedFilePaths: Set<string>;
    try {
      const packed = spawnSync('pnpm', ['pack', '--pack-destination', packDir, '--config.ignore-scripts=true'], {
        cwd: process.cwd(),
        encoding: 'utf-8',
      });
      assert.equal(packed.status, 0, packed.stderr || packed.stdout);

      const tarballName = readdirSync(packDir).find((file) => file.endsWith('.tgz'));
      assert.ok(tarballName, `expected pnpm pack to produce a tarball\n${packed.stdout}`);

      const listing = spawnSync('tar', ['-tzf', join(packDir, tarballName)], { encoding: 'utf-8' });
      assert.equal(listing.status, 0, listing.stderr || listing.stdout);

      packedFilePaths = new Set(
        listing.stdout
          .split(/\r?\n/)
          .map((line) => line.trim())
          .map((entry) => entry.replace(/^\.\//, '').replace(/^package\//, ''))
          .filter((entry) => entry !== '' && !entry.endsWith('/')),
      );
    } finally {
      rmSync(packDir, { recursive: true, force: true });
    }

    const hasPacked = (path: string): boolean => packedFilePaths.has(path);
    const somePacked = (predicate: (path: string) => boolean): boolean =>
      [...packedFilePaths].some(predicate);

    assert.ok(hasPacked('dist/cli/omx.js'), 'expected pnpm pack output to include dist/cli/omx.js');

    const packagedHarnessPath = process.platform === 'win32' ? 'bin/omx-explore-harness.exe' : 'bin/omx-explore-harness';

    assert.equal(hasPacked(packagedHarnessPath), false, `did not expect ${packagedHarnessPath} in pnpm pack output`);
    assert.equal(hasPacked('bin/omx-explore-harness.meta.json'), false, 'did not expect packaged explore harness metadata in pnpm pack output');
    assert.equal(somePacked((path) => path.includes('bin/native/')), false, 'did not expect staged native binaries in pnpm pack output');
    assert.ok(hasPacked('Cargo.toml'), 'expected pnpm pack output to include Cargo.toml');
    assert.ok(hasPacked('Cargo.lock'), 'expected pnpm pack output to include Cargo.lock');
    assert.ok(hasPacked('crates/omx-explore/Cargo.toml'), 'expected pnpm pack output to include crates/omx-explore/Cargo.toml');
    assert.ok(hasPacked('crates/omx-explore/src/main.rs'), 'expected pnpm pack output to include crates/omx-explore/src/main.rs');
    assert.ok(hasPacked('.agents/plugins/marketplace.json'), 'expected pnpm pack output to include .agents/plugins/marketplace.json');
    assert.ok(hasPacked('plugins/oh-my-codex/.codex-plugin/plugin.json'), 'expected pnpm pack output to include plugins/oh-my-codex/.codex-plugin/plugin.json');
    assert.ok(hasPacked('plugins/oh-my-codex/.mcp.json'), 'expected pnpm pack output to include plugins/oh-my-codex/.mcp.json');
    assert.ok(hasPacked('plugins/oh-my-codex/.app.json'), 'expected pnpm pack output to include plugins/oh-my-codex/.app.json');
    assert.ok(hasPacked('plugins/oh-my-codex/hooks/hooks.json'), 'expected pnpm pack output to include plugins/oh-my-codex/hooks/hooks.json');
    assert.ok(hasPacked('plugins/oh-my-codex/hooks/codex-native-hook.mjs'), 'expected pnpm pack output to include plugins/oh-my-codex/hooks/codex-native-hook.mjs');
    assert.ok(hasPacked('dist/mcp/state-server.js'), 'expected pnpm pack output to include dist/mcp/state-server.js for omx mcp-serve');
    assert.ok(hasPacked('dist/mcp/memory-server.js'), 'expected pnpm pack output to include dist/mcp/memory-server.js for omx mcp-serve');
    assert.ok(hasPacked('dist/mcp/code-intel-server.js'), 'expected pnpm pack output to include dist/mcp/code-intel-server.js for omx mcp-serve');
    assert.ok(hasPacked('dist/mcp/trace-server.js'), 'expected pnpm pack output to include dist/mcp/trace-server.js for omx mcp-serve');
    assert.ok(hasPacked('dist/mcp/wiki-server.js'), 'expected pnpm pack output to include dist/mcp/wiki-server.js for omx mcp-serve');

    const manifest = readCatalogManifest(process.cwd());
    const installableSkillNames = [...getSetupInstallableSkillNames(manifest)].sort();
    for (const skillName of installableSkillNames) {
      assert.equal(
        packedFilePaths.has(`plugins/oh-my-codex/skills/${skillName}/SKILL.md`),
        true,
        `expected pnpm pack output to include mirrored plugin ${skillName} skill`,
      );
    }
    const installableNativeAgentNames = [...getInstallableNativeAgentNames(manifest)].sort();
    for (const agentName of installableNativeAgentNames) {
      assert.equal(
        packedFilePaths.has(`prompts/${agentName}.md`),
        true,
        `expected pnpm pack output to include prompt for native agent ${agentName}`,
      );
    }
    assert.ok(hasPacked('skills/ralph/SKILL.md'), 'expected pnpm pack output to keep canonical root skills');
    assert.ok(hasPacked('prompts/executor.md'), 'expected pnpm pack output to keep prompts');
    assert.ok(hasPacked('templates/AGENTS.md'), 'expected pnpm pack output to keep templates');
    assert.equal(somePacked((path) => path === 'agents' || path.startsWith('agents/')), false, 'did not expect generated root native agent TOMLs in package output');
    assert.equal(somePacked((path) =>
      path === 'plugins/oh-my-codex/hooks.json'
      || path === 'plugins/oh-my-codex/.codex/hooks.json'
      || path === 'plugins/oh-my-codex/.codex-plugin/hooks.json'
      || path.startsWith('plugins/oh-my-codex/.omx/hooks/')), false, 'did not expect setup-owned hook assets inside the installable plugin bundle');
  });
});
