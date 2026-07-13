import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
	INTEROP_CAVEMAN_LEVELS,
	resolveInteropCavemanActivation,
} from "../interop-caveman.js";

describe("resolveInteropCavemanActivation", () => {
	it("returns null when OMX_INTEROP_CAVEMAN_LEVEL is unset", () => {
		let warned = false;
		const result = resolveInteropCavemanActivation({}, () => {
			warned = true;
		});
		assert.equal(result, null);
		assert.equal(warned, false);
	});

	it("returns null when OMX_INTEROP_CAVEMAN_LEVEL is blank", () => {
		let warned = false;
		const result = resolveInteropCavemanActivation(
			{ OMX_INTEROP_CAVEMAN_LEVEL: "   " },
			() => {
				warned = true;
			},
		);
		assert.equal(result, null);
		assert.equal(warned, false);
	});

	it("maps every valid level to `use caveman <level> mode`", () => {
		for (const level of INTEROP_CAVEMAN_LEVELS) {
			const result = resolveInteropCavemanActivation(
				{ OMX_INTEROP_CAVEMAN_LEVEL: level },
				() => {
					assert.fail(`valid level ${level} should not warn`);
				},
			);
			assert.deepEqual(result, {
				level,
				activation: `use caveman ${level} mode`,
			});
		}
	});

	it("produces `use caveman wenyan-ultra mode` for wenyan-ultra", () => {
		const result = resolveInteropCavemanActivation({
			OMX_INTEROP_CAVEMAN_LEVEL: "wenyan-ultra",
		});
		assert.equal(result?.activation, "use caveman wenyan-ultra mode");
	});

	it("is case-insensitive and trims surrounding whitespace", () => {
		const result = resolveInteropCavemanActivation({
			OMX_INTEROP_CAVEMAN_LEVEL: "  WenYan-Ultra  ",
		});
		assert.deepEqual(result, {
			level: "wenyan-ultra",
			activation: "use caveman wenyan-ultra mode",
		});
	});

	it("warns and returns null for an invalid level without throwing", () => {
		const warnings: string[] = [];
		const result = resolveInteropCavemanActivation(
			{ OMX_INTEROP_CAVEMAN_LEVEL: "turbo" },
			(message) => warnings.push(message),
		);
		assert.equal(result, null);
		assert.deepEqual(warnings, [
			"[omx] ignoring invalid OMX_INTEROP_CAVEMAN_LEVEL=turbo",
		]);
	});

	it("does not throw when no warn callback is supplied for an invalid level", () => {
		const originalWrite = process.stderr.write.bind(process.stderr);
		const captured: string[] = [];
		process.stderr.write = ((chunk: string | Uint8Array) => {
			captured.push(String(chunk));
			return true;
		}) as typeof process.stderr.write;
		try {
			const result = resolveInteropCavemanActivation({
				OMX_INTEROP_CAVEMAN_LEVEL: "bogus",
			});
			assert.equal(result, null);
		} finally {
			process.stderr.write = originalWrite;
		}
		assert.ok(
			captured.some((line) =>
				line.includes("ignoring invalid OMX_INTEROP_CAVEMAN_LEVEL=bogus"),
			),
		);
	});
});
