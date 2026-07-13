/**
 * OMC<->OMX interop: deterministic codex-side caveman activation.
 *
 * When the OMC leader launches the codex (OMX) pane in interop it sets
 * `OMX_INTEROP_CAVEMAN_LEVEL=<level>`. On a top-level codex SessionStart we
 * activate the codex caveman skill at that level exactly once by injecting the
 * natural-language activation string (`use caveman <level> mode`) into codex's
 * own tmux pane, reusing the readiness-aware pane injection so keystrokes are
 * not dropped during TUI boot.
 */

import { resolveCodexPane } from "../tmux-hook-engine.js";
import { safeString } from "./utils.js";
import {
	evaluatePaneInjectionReadiness,
	sendPaneInput,
} from "./team-tmux-guard.js";

export const INTEROP_CAVEMAN_LEVELS = [
	"lite",
	"full",
	"ultra",
	"wenyan-lite",
	"wenyan-full",
	"wenyan-ultra",
] as const;

export type InteropCavemanLevel = (typeof INTEROP_CAVEMAN_LEVELS)[number];

export interface InteropCavemanActivation {
	level: InteropCavemanLevel;
	activation: string;
}

/**
 * Read + validate `OMX_INTEROP_CAVEMAN_LEVEL` from the given env.
 * - unset/blank -> null (no-op)
 * - invalid -> warn to stderr and return null (no throw)
 * - valid -> { level, activation: `use caveman <level> mode` }
 */
export function resolveInteropCavemanActivation(
	env: NodeJS.ProcessEnv = process.env,
	warn: (message: string) => void = (message) => {
		process.stderr.write(`${message}\n`);
	},
): InteropCavemanActivation | null {
	const raw = safeString(env.OMX_INTEROP_CAVEMAN_LEVEL).trim();
	if (!raw) return null;
	const level = raw.toLowerCase();
	if (!(INTEROP_CAVEMAN_LEVELS as readonly string[]).includes(level)) {
		warn(`[omx] ignoring invalid OMX_INTEROP_CAVEMAN_LEVEL=${raw}`);
		return null;
	}
	return {
		level: level as InteropCavemanLevel,
		activation: `use caveman ${level} mode`,
	};
}

export interface InteropCavemanInjectionDeps {
	resolvePane?: () => string;
	evaluateReadiness?: typeof evaluatePaneInjectionReadiness;
	sendInput?: typeof sendPaneInput;
	readinessAttempts?: number;
	readinessDelayMs?: number;
	/**
	 * Overall wall-clock budget for the readiness poll. Bounds the aggregate of
	 * the (individually-timed-out) tmux calls so a wedged tmux cannot stall the
	 * awaited SessionStart hook for minutes. Default 4000ms.
	 */
	deadlineMs?: number;
	now?: () => number;
	sleep?: (ms: number) => Promise<void>;
	env?: NodeJS.ProcessEnv;
}

export interface InteropCavemanInjectionResult {
	injected: boolean;
	reason: string;
	paneTarget?: string;
}

/**
 * Resolve codex's own tmux pane, wait until it can accept input using the
 * shared readiness machinery, then inject + submit the activation string.
 * No-ops quietly when not inside tmux or when no self pane is resolvable.
 */
export async function performInteropCavemanInjection(
	activation: InteropCavemanActivation,
	deps: InteropCavemanInjectionDeps = {},
): Promise<InteropCavemanInjectionResult> {
	const env = deps.env ?? process.env;
	const resolvePane = deps.resolvePane ?? resolveCodexPane;
	const evaluateReadiness =
		deps.evaluateReadiness ?? evaluatePaneInjectionReadiness;
	const sendInput = deps.sendInput ?? sendPaneInput;
	const attempts = Math.max(1, deps.readinessAttempts ?? 20);
	const delayMs = Math.max(0, deps.readinessDelayMs ?? 150);
	const deadlineMs = Math.max(0, deps.deadlineMs ?? 4000);
	const now = deps.now ?? (() => Date.now());
	const sleep =
		deps.sleep ?? ((ms: number) => new Promise((r) => setTimeout(r, ms)));

	if (!safeString(env.TMUX).trim()) {
		return { injected: false, reason: "not_in_tmux" };
	}
	const paneTarget = safeString(resolvePane()).trim();
	if (!paneTarget) {
		return { injected: false, reason: "no_self_pane" };
	}

	const startedAt = now();
	for (let attempt = 0; attempt < attempts; attempt += 1) {
		if (deadlineMs > 0 && now() - startedAt > deadlineMs) {
			return { injected: false, reason: "deadline", paneTarget };
		}
		let ready = false;
		try {
			const guard = await evaluateReadiness(paneTarget, {
				skipIfScrolling: true,
			});
			ready = Boolean(guard?.ok);
		} catch {
			ready = false;
		}
		if (ready) {
			const result = await sendInput({
				paneTarget,
				prompt: activation.activation,
				submitDelayMs: 25,
			});
			if (result?.ok) {
				return { injected: true, reason: "injected", paneTarget };
			}
			return {
				injected: false,
				reason: safeString(result?.reason) || "send_failed",
				paneTarget,
			};
		}
		if (attempt < attempts - 1) await sleep(delayMs);
	}
	return { injected: false, reason: "pane_never_ready", paneTarget };
}
