# oh-my-codex — Codebase Guide

Machine-generated map of this repository, built to get a new reader
productive fast. Grounded in a `codegraph` index (805 files, 15,286 nodes,
58,007 edges), `ast-grep` structural queries, and `rtk` directory scans.

> Interactive version: open [`explorer.html`](./explorer.html) for a
> searchable, diagram-rendering browser of these same docs (Datastar +
> Mermaid).

## What this project is

`oh-my-codex` (binary `omx`, package `oh-my-codex`, v0.19.1) is a
multi-agent orchestration layer for the OpenAI Codex CLI. It ships:

- A CLI (`omx`) for setup, diagnostics, team runs, and workflow loops.
- A catalog of 36 agent prompts installed as Codex slash-commands.
- 35+ workflow skills (SKILL.md files).
- Six MCP servers (state, memory, wiki, trace, code-intel, bridge).
- An `AGENTS.md` orchestration brain installed into `~/.codex/`.
- Native Rust crates for the interactive shell, mux, and code explorer.

It does not replace Codex; it wraps and configures it, then coordinates
one or many Codex/Claude worker sessions through a staged pipeline.

## Read in this order

1. [`architecture.md`](./architecture.md) — the big picture with diagrams:
   system context, component map, the Autopilot pipeline, team
   orchestration, MCP servers, and mode/keyword routing.
2. [`data-flow.md`](./data-flow.md) — sequence diagrams for the flows that
   matter: a session launch, an Autopilot run, a team run, and MCP state
   reads/writes.
3. [`modules.md`](./modules.md) — a module-by-module reference of `src/`
   and the Rust crates, with the "why it exists" for each.

## Fast facts

| Dimension | Value |
|-----------|-------|
| Package / binary | `oh-my-codex` / `omx` |
| Version | 0.19.1 |
| Module system | ESM (`"type": "module"`) |
| Primary language | TypeScript (738 files) |
| Native code | Rust (37 files, 6 crates) |
| Eval scripts | Python (4 files under `src/scripts/eval/`) |
| CLI entry | `dist/cli/omx.js` → `src/cli/omx.ts` → `src/cli/index.ts` |
| Library entry | `src/index.ts` |
| Agents | 36 (see `prompts/*.md`) |
| MCP servers | 6 (`omx-state`, `omx-memory`, `omx-wiki`, `omx-trace`, `omx-code-intel`, `omx-h*` bridge) |
| Pipeline stages | deep-interview → ralplan → ultragoal → code-review → ultraqa |
| Runtime state dir | `.omx/` (project) and `~/.codex/` (global config) |

## Regenerating this guide

These files are hand-authored from tool output; there is no generator to
re-run. To refresh the underlying data:

```bash
codegraph status          # index stats used in this guide
codegraph files           # file inventory
rg -o 'name:\s*"([^"]+)"' -r '$1' src/agents/definitions.ts | sort -u
ast-grep run --pattern 'export function $F($$$) { $$$ }' --lang ts src
```
