import { mkdtempSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import { ensureReusableNodeModules } from "../utils/repo-deps.js";

export {
	hasUsableNodeModules,
	resolveGitCommonDir,
	resolveReusableNodeModulesSource,
} from "../utils/repo-deps.js";

export const PACKED_INSTALL_SMOKE_CORE_COMMANDS = [
	["--help"],
	["version"],
	["api", "--help"],
	["sparkshell", "--help"],
] as const;

export const PACKED_INSTALL_NATIVE_HOOK_SMOKE_EVENTS = [
	"SessionStart",
	"PreToolUse",
	"PostToolUse",
	"UserPromptSubmit",
	"PreCompact",
	"PostCompact",
	"Stop",
] as const;

function usage(): string {
	return [
		"Usage: node scripts/smoke-packed-install.mjs",
		"",
		"Creates a pnpm tarball, installs it into an isolated host project, and smoke tests the installed omx CLI.",
		"Release smoke stays intentionally minimal: install + boot + 1-2 core commands only.",
	].join("\n");
}

interface EnsureRepoDepsOptions {
	gitRunner?: typeof spawnSync;
	install?: (cwd: string) => void;
	log?: (message: string) => void;
}

interface EnsureRepoDepsResult {
	strategy: string;
	nodeModulesPath: string;
	sourceNodeModulesPath?: string;
}

function formatCommandFailure(
	cmd: string,
	args: string[],
	result: { stdout?: string; stderr?: string },
): string {
	return [
		`Command failed: ${cmd} ${args.join(" ")}`,
		result.stdout?.trim() ? `stdout:\n${result.stdout.trim()}` : "",
		result.stderr?.trim() ? `stderr:\n${result.stderr.trim()}` : "",
	]
		.filter(Boolean)
		.join("\n\n");
}

export function ensureRepoDependencies(
	repoRoot: string,
	options: EnsureRepoDepsOptions = {},
): EnsureRepoDepsResult {
	const {
		gitRunner = spawnSync,
		install = (cwd: string) => {
			const result = spawnSync("pnpm", ["install", "--frozen-lockfile"], {
				cwd,
				encoding: "utf-8",
				stdio: "pipe",
			});
			if (result.status !== 0) {
				throw new Error(
					formatCommandFailure(
						"pnpm",
						["install", "--frozen-lockfile"],
						result,
					),
				);
			}
		},
		log = () => {},
	} = options;

	const reusable = ensureReusableNodeModules(repoRoot, { gitRunner });
	if (reusable.strategy === "existing") {
		return reusable;
	}
	if (reusable.strategy === "symlink") {
		log(
			`[smoke:packed-install] Reusing node_modules from ${reusable.sourceNodeModulesPath}`,
		);
		return reusable;
	}

	log(
		"[smoke:packed-install] Installing repo dependencies with pnpm install --frozen-lockfile",
	);
	install(repoRoot);
	return {
		strategy: "installed",
		nodeModulesPath: join(repoRoot, "node_modules"),
	};
}

function parseArgs(argv: string[]): void {
	for (const token of argv) {
		if (token === "--help" || token === "-h") {
			console.log(usage());
			process.exit(0);
		}
		throw new Error(`Unknown argument: ${token}\n${usage()}`);
	}
}

function run(
	cmd: string,
	args: readonly string[],
	options: Record<string, unknown> = {},
): ReturnType<typeof spawnSync> {
	const result = spawnSync(cmd, [...args], {
		encoding: "utf-8",
		stdio: "pipe",
		...options,
	});
	if (result.status !== 0) {
		throw new Error(formatCommandFailure(cmd, [...args], result));
	}
	return result;
}

function binName(name: string): string {
	return process.platform === "win32" ? `${name}.cmd` : name;
}

export function validateHookStdout(eventName: string, stdout: string): void {
	const trimmed = stdout.trim();
	if (!trimmed) return;
	try {
		JSON.parse(trimmed);
	} catch (error) {
		throw new Error(
			`native hook ${eventName} emitted invalid JSON stdout: ${error instanceof Error ? error.message : String(error)}`,
		);
	}
}

export function buildNativeHookSmokePayload(
	eventName: (typeof PACKED_INSTALL_NATIVE_HOOK_SMOKE_EVENTS)[number],
	smokeCwd: string,
): Record<string, unknown> {
	const base = {
		hook_event_name: eventName,
		session_id: `packed-install-smoke-${eventName}`,
		cwd: smokeCwd,
	};
	switch (eventName) {
		case "SessionStart":
			return {
				...base,
				transcript_path: join(smokeCwd, "nonexistent-transcript.jsonl"),
			};
		case "PreToolUse":
			return {
				...base,
				tool_name: "Bash",
				tool_use_id: "packed-install-smoke-tool",
				tool_input: { command: "echo packed install smoke" },
			};
		case "PostToolUse":
			return {
				...base,
				tool_name: "Bash",
				tool_use_id: "packed-install-smoke-tool",
				tool_input: { command: "echo packed install smoke" },
				tool_response: {
					exit_code: 0,
					stdout: "packed install smoke\n",
					stderr: "",
				},
			};
		case "UserPromptSubmit":
			return {
				...base,
				transcript_path: join(smokeCwd, "nonexistent-transcript.jsonl"),
				prompt: "packed install native hook smoke test",
			};
		case "PreCompact":
		case "PostCompact":
		case "Stop":
			return base;
	}
}

function smokeInstalledNativeHookDist(installDir: string): void {
	const packageRoot = join(installDir, "node_modules", "oh-my-codex");
	const hookScript = join(
		packageRoot,
		"dist",
		"scripts",
		"codex-native-hook.js",
	);
	const smokeCwd = mkdtempSync(join(tmpdir(), "omx-packed-hook-smoke-"));
	try {
		for (const eventName of PACKED_INSTALL_NATIVE_HOOK_SMOKE_EVENTS) {
			const payload = buildNativeHookSmokePayload(eventName, smokeCwd);
			const result = run(process.execPath, [realpathSync(hookScript)], {
				cwd: smokeCwd,
				env: {
					...process.env,
					OMX_NATIVE_HOOK_DOCTOR_SMOKE: "1",
					OMX_ROOT: join(smokeCwd, ".omx-packed-hook-root"),
					OMX_SESSION_ID: `packed-install-smoke-${eventName}`,
					OMX_SOURCE_CWD: smokeCwd,
					OMX_STARTUP_CWD: smokeCwd,
				},
				input: JSON.stringify(payload),
			});
			validateHookStdout(eventName, result.stdout as string);
		}
	} finally {
		rmSync(smokeCwd, { recursive: true, force: true });
	}
}

export function parsePnpmPackTarballPath(stdout: string): string {
	const lines = stdout
		.split("\n")
		.map((line) => line.trim())
		.filter((line) => line.length > 0);
	for (let i = lines.length - 1; i >= 0; i--) {
		if (lines[i].endsWith(".tgz")) {
			return lines[i];
		}
	}
	throw new Error(`pnpm pack did not return a tarball path: ${stdout.trim()}`);
}

async function main(): Promise<void> {
	parseArgs(process.argv.slice(2));

	const repoRoot = process.cwd();
	const tempRoot = mkdtempSync(join(tmpdir(), "omx-packed-install-"));
	const installDir = join(tempRoot, "host");
	mkdirSync(installDir, { recursive: true });
	writeFileSync(
		join(installDir, "package.json"),
		`${JSON.stringify({ name: "omx-packed-install-smoke-host", version: "0.0.0", private: true }, null, 2)}\n`,
	);

	let tarballPath: string | undefined;
	try {
		ensureRepoDependencies(repoRoot, {
			log: (message: string) => console.log(message),
		});

		const pack = run("pnpm", ["pack"], { cwd: repoRoot });
		tarballPath = parsePnpmPackTarballPath(pack.stdout as string);

		run(
			"pnpm",
			["--dir", installDir, "add", tarballPath, "--ignore-workspace"],
			{ cwd: installDir },
		);

		const omxPath = join(installDir, "node_modules", ".bin", binName("omx"));
		for (const argv of PACKED_INSTALL_SMOKE_CORE_COMMANDS) {
			run(omxPath, argv, { cwd: repoRoot });
		}
		smokeInstalledNativeHookDist(installDir);

		console.log("packed install smoke: PASS");
	} finally {
		if (tarballPath) rmSync(tarballPath, { force: true });
		rmSync(tempRoot, { recursive: true, force: true });
	}
}

if (
	process.argv[1] &&
	import.meta.url === pathToFileURL(process.argv[1]).href
) {
	main().catch((error) => {
		console.error(
			`packed install smoke: FAIL\n${error instanceof Error ? error.message : String(error)}`,
		);
		process.exit(1);
	});
}
