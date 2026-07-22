import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
	INTEROP_CONTEXT_MODES,
	resolveInteropContextNotice,
} from "../interop-context.js";

const ENABLED_ENV = {
	OMX_OMC_INTEROP_ENABLED: "1",
	OMX_OMC_INTEROP_MODE: "active",
	OMX_OMC_INTEROP_SESSION_ID: "interop-ab12cd34",
	OMX_OMC_INTEROP_DIR: "/tmp/omc/state/interop",
};

describe("resolveInteropContextNotice", () => {
	it("returns null when OMX_OMC_INTEROP_ENABLED is unset", () => {
		let warned = false;
		const result = resolveInteropContextNotice({}, () => {
			warned = true;
		});
		assert.equal(result, null);
		assert.equal(warned, false);
	});

	it("returns null when OMX_OMC_INTEROP_ENABLED is not '1'", () => {
		const result = resolveInteropContextNotice(
			{ ...ENABLED_ENV, OMX_OMC_INTEROP_ENABLED: "true" },
			() => {
				assert.fail("should not warn");
			},
		);
		assert.equal(result, null);
	});

	it("returns null when OMX_OMC_INTEROP_DIR is missing or blank", () => {
		for (const dir of [undefined, "", "   "]) {
			const result = resolveInteropContextNotice(
				{ ...ENABLED_ENV, OMX_OMC_INTEROP_DIR: dir },
				() => {
					assert.fail("should not warn");
				},
			);
			assert.equal(result, null);
		}
	});

	it("builds a notice containing session id, mode, and dir when enabled", () => {
		const result = resolveInteropContextNotice(ENABLED_ENV, () => {
			assert.fail("valid env should not warn");
		});
		assert.ok(result);
		assert.equal(result.sessionId, "interop-ab12cd34");
		assert.equal(result.mode, "active");
		assert.equal(result.dir, "/tmp/omc/state/interop");
		assert.ok(result.notice.includes("interop-ab12cd34"));
		assert.ok(result.notice.includes("(mode: active)"));
		assert.ok(result.notice.includes("/tmp/omc/state/interop/tasks/*.json"));
		assert.ok(result.notice.includes("/tmp/omc/state/interop/messages/*.json"));
	});

	it("accepts every declared mode without warning", () => {
		for (const mode of INTEROP_CONTEXT_MODES) {
			const result = resolveInteropContextNotice(
				{ ...ENABLED_ENV, OMX_OMC_INTEROP_MODE: mode },
				() => {
					assert.fail(`valid mode ${mode} should not warn`);
				},
			);
			assert.equal(result?.mode, mode);
		}
	});

	it("defaults to observe without warning when mode is unset", () => {
		const result = resolveInteropContextNotice(
			{ ...ENABLED_ENV, OMX_OMC_INTEROP_MODE: undefined },
			() => {
				assert.fail("unset mode should not warn");
			},
		);
		assert.equal(result?.mode, "observe");
	});

	it("warns and falls back to observe for an unknown mode", () => {
		const warnings: string[] = [];
		const result = resolveInteropContextNotice(
			{ ...ENABLED_ENV, OMX_OMC_INTEROP_MODE: "turbo" },
			(message) => warnings.push(message),
		);
		assert.equal(result?.mode, "observe");
		assert.deepEqual(warnings, [
			"[omx] unknown OMX_OMC_INTEROP_MODE=turbo; defaulting to observe",
		]);
	});

	it("trims whitespace and lowercases the mode", () => {
		const result = resolveInteropContextNotice(
			{
				OMX_OMC_INTEROP_ENABLED: " 1 ",
				OMX_OMC_INTEROP_MODE: "  Active  ",
				OMX_OMC_INTEROP_SESSION_ID: "  interop-ab12cd34  ",
				OMX_OMC_INTEROP_DIR: "  /tmp/omc/state/interop  ",
			},
			() => {
				assert.fail("should not warn");
			},
		);
		assert.ok(result);
		assert.equal(result.sessionId, "interop-ab12cd34");
		assert.equal(result.mode, "active");
		assert.equal(result.dir, "/tmp/omc/state/interop");
	});

	it("falls back to a placeholder session id when unset", () => {
		const result = resolveInteropContextNotice({
			...ENABLED_ENV,
			OMX_OMC_INTEROP_SESSION_ID: undefined,
		});
		assert.equal(result?.sessionId, "(unknown)");
		assert.ok(result?.notice.includes("(unknown)"));
	});

	it("does not throw when no warn callback is supplied for an unknown mode", () => {
		const originalWrite = process.stderr.write.bind(process.stderr);
		const captured: string[] = [];
		process.stderr.write = ((chunk: string | Uint8Array) => {
			captured.push(String(chunk));
			return true;
		}) as typeof process.stderr.write;
		try {
			const result = resolveInteropContextNotice({
				...ENABLED_ENV,
				OMX_OMC_INTEROP_MODE: "bogus",
			});
			assert.equal(result?.mode, "observe");
		} finally {
			process.stderr.write = originalWrite;
		}
		assert.ok(
			captured.some((line) =>
				line.includes("unknown OMX_OMC_INTEROP_MODE=bogus"),
			),
		);
	});
});
