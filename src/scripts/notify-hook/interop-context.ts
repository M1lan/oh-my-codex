/**
 * OMC<->OMX interop: codex-side interop context notice.
 *
 * When oh-my-claudecode's `omc interop` launches the codex (OMX) pane it sets
 * `OMX_OMC_INTEROP_ENABLED=1`, `OMX_OMC_INTEROP_MODE` ('observe'|'active'),
 * `OMX_OMC_INTEROP_SESSION_ID`, and `OMX_OMC_INTEROP_DIR` (absolute path to
 * the shared interop state dir containing config.json, tasks/, messages/).
 * On a top-level codex SessionStart we inject a concise notice into codex's
 * own tmux pane exactly once so the model knows interop is active and where
 * the shared state lives, reusing the readiness-aware pane injection from the
 * interop caveman activation.
 */

import {
	type InteropCavemanInjectionDeps,
	type InteropCavemanInjectionResult,
	performInteropCavemanInjection,
} from "./interop-caveman.js";
import { safeString } from "./utils.js";

export const INTEROP_CONTEXT_MODES = ["observe", "active"] as const;

export type InteropContextMode = (typeof INTEROP_CONTEXT_MODES)[number];

export interface InteropContextNotice {
	sessionId: string;
	mode: InteropContextMode;
	dir: string;
	notice: string;
}

/**
 * Read + validate the OMX_OMC_INTEROP_* contract from the given env.
 * - `OMX_OMC_INTEROP_ENABLED` !== '1' or blank `OMX_OMC_INTEROP_DIR` -> null
 * - unknown `OMX_OMC_INTEROP_MODE` -> warn to stderr and fall back to 'observe'
 * - valid -> { sessionId, mode, dir, notice } with a concise injection notice
 */
export function resolveInteropContextNotice(
	env: NodeJS.ProcessEnv = process.env,
	warn: (message: string) => void = (message) => {
		process.stderr.write(`${message}\n`);
	},
): InteropContextNotice | null {
	if (safeString(env.OMX_OMC_INTEROP_ENABLED).trim() !== "1") return null;
	const dir = safeString(env.OMX_OMC_INTEROP_DIR).trim();
	if (!dir) return null;

	const rawMode = safeString(env.OMX_OMC_INTEROP_MODE).trim();
	const normalizedMode = rawMode.toLowerCase();
	let mode: InteropContextMode = "observe";
	if ((INTEROP_CONTEXT_MODES as readonly string[]).includes(normalizedMode)) {
		mode = normalizedMode as InteropContextMode;
	} else if (rawMode) {
		warn(
			`[omx] unknown OMX_OMC_INTEROP_MODE=${rawMode}; defaulting to observe`,
		);
	}

	const sessionId =
		safeString(env.OMX_OMC_INTEROP_SESSION_ID).trim() || "(unknown)";
	const notice =
		`OMC<->OMX interop session ${sessionId} is active (mode: ${mode}). ` +
		`Shared interop state: ${dir}. ` +
		`To coordinate with OMC: read pending tasks targeted at you from ${dir}/tasks/*.json ` +
		`(fields: id, source, target, type, description, status), ` +
		`write results by updating the task JSON (status: completed|failed, result), ` +
		`and exchange messages via ${dir}/messages/*.json. ` +
		`Check for new tasks/messages when asked to coordinate with OMC.`;

	return { sessionId, mode, dir, notice };
}

/**
 * Inject the interop context notice into codex's own tmux pane using the
 * shared readiness-aware pane injection machinery.
 */
export function performInteropContextInjection(
	notice: InteropContextNotice,
	deps: InteropCavemanInjectionDeps = {},
): Promise<InteropCavemanInjectionResult> {
	return performInteropCavemanInjection({ activation: notice.notice }, deps);
}
