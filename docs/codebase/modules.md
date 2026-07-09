# Module reference

Every top-level `src/` subsystem and native crate, with the reason it
exists and its notable files. Sizes are approximate (from `rtk ls`). Use
`codegraph node <symbol>` or `codegraph explore <query>` to drill in.

## Entry points

| File | Role |
|------|------|
| `src/cli/omx.ts` | Thin binary shim (836 B) → `cli/index.ts`. |
| `src/cli/index.ts` | Command router / arg parser (~208 KB). The spine. |
| `src/index.ts` | Library API surface (setup, doctor, version, agents, hud, vscode). |

## `src/cli/` — command surface

The user-facing commands. Largest first:

| File | Purpose |
|------|---------|
| `index.ts` | Master command dispatch, session launch, flag handling. |
| `setup.ts` | Install/refresh `~/.codex/` (config, prompts, skills, AGENTS.md); interop verifiers. |
| `doctor.ts` | Environment + install diagnostics. |
| `team.ts` | Multi-agent team runs. |
| `update.ts` | Version-check and update flow. |
| `ultragoal.ts` | Durable multi-goal ledger workflow. |
| `uninstall.ts` | Remove OMX-managed assets. |
| `plugin-marketplace.ts` | Plugin discovery/install. |
| `ralph.ts` | Persistence loop command. |
| `mission.ts` | Mission workflow. |
| `sparkshell.ts` | Launch the Rust interactive shell. |
| `tmux-hook.ts` | tmux capture-pane hook engine glue. |
| `question.ts`, `autoresearch*.ts` | Q&A and research intake/guided flows. |
| `mcp-serve.ts`, `mcp-parity.ts` | Serve MCP servers; verify parity. |
| `agents.ts`, `agents-init.ts`, `native-assets.ts` | Agent catalog + native config install. |

## `src/pipeline/` — Autopilot stages

Sequences deep-interview → ralplan → ultragoal → code-review → ultraqa.

| File | Purpose |
|------|---------|
| `orchestrator.ts` | `runPipeline`, `createAutopilotPipelineConfig`, resume/cancel. |
| `types.ts` | `PipelineStage`, `StageContext`, `StageResult`, config types. |
| `stages/base.ts` | Shared stage scaffolding. |
| `stages/{deep-interview,ralplan,ultragoal,code-review,ultraqa}.ts` | The five stages. |
| `stages/{team-exec,ralph-verify}.ts` | Legacy adapters still selectable. |
| `review-verdict.ts` | Verdict parsing for the review stage. |

## `src/team/` — multi-agent coordination

| File | Purpose |
|------|---------|
| `api-interop.ts` (~55 KB) | Cross-CLI (Codex↔Claude) API contract. |
| `coordination-protocol.ts` | Leader/worker handshake protocol. |
| `mcp-comm.ts` | Leader↔worker messaging over MCP. |
| `dag-schema.ts` | Task DAG schema + scheduling. |
| `allocation-policy.ts` | Which worker gets which task. |
| `delegation-policy.ts` | When to delegate vs do inline. |
| `model-contract.ts` | Per-role model selection contract. |
| `tmux-session.ts` | Pane/session creation (routes through rmux/tmux). |
| `commit-hygiene.ts` | Incremental-commit discipline. |
| `followup-planner.ts` | Post-run follow-up task generation. |
| `idle-nudge.ts`, `leader-activity.ts` | Idle detection + leader nudges. |
| `current-task-baseline.ts`, `delivery-log.ts` | Per-task state + audit log. |

## `src/mcp/` — MCP servers

| Server / file | Purpose |
|---------------|---------|
| `bootstrap.ts` | Register + launch all servers. |
| `state-server.ts` → `omx-state` | Lifecycle state, notepad. |
| `memory-server.ts` → `omx-memory` | Project memory across sessions. |
| `wiki-server.ts` → `omx-wiki` | Wiki/knowledge lookups. |
| `trace-server.ts` → `omx-trace` | Debug trace capture. |
| `code-intel-server.ts` → `omx-code-intel` | Code intelligence queries. |
| `h*-bridge.ts` + `h*-server.ts` → `omx-h*` | External bridge server (identifier masked per house rule; real name in `src/mcp/`). |
| `state-paths.ts` | Central on-disk path resolution. |

## `src/hooks/` + `src/modes/` — routing & lifecycle

| File | Purpose |
|------|---------|
| `keyword-detector.ts` (~76 KB) | Map prompt text → workflow mode. |
| `keyword-registry.ts` | Keyword → mode table. |
| `codebase-map.ts` | Build a project map for context. |
| `agents-overlay.ts` | Overlay agent behavior onto sessions. |
| `triage-{heuristic,state,config}.ts` | Task triage. |
| `task-size-detector.ts` | Estimate task size for routing. |
| `session.ts` | Session state read/write. |
| `modes/base.ts` | Mode base definitions. |

## `src/state/` — workflow state machine

| File | Purpose |
|------|---------|
| `operations.ts` (~36 KB) | Core state read/write operations. |
| `workflow-transition.ts` (~33 KB) | Mode transition logic. |
| `workflow-transition-reconcile.ts` | Reconcile conflicting transitions. |
| `skill-active.ts` | Track the currently active skill. |
| `mode-state-context.ts` | Capture tmux/window context for a mode. |

## Workflow modules

| Dir | Purpose |
|-----|---------|
| `autopilot/` | Full autonomous execution loop. |
| `ralph/` | Persistence-until-done loop. |
| `ralplan/` | Consensus planning loop. |
| `ultragoal/` | Ordered multi-goal ledger. |
| `autoresearch/` | Parallel research orchestration. |
| `goal-workflows/` | Shared goal-loop primitives. |
| `planning/` | Plan-file generation. |
| `question/` | Q&A intake. |
| `verification/` | Verify/QA helpers. |
| `subagents/`, `leader/` | Sub-agent spawn + leader control. |

## Platform & IO modules

| Dir | Purpose |
|-----|---------|
| `config/` | Generate/merge `config.toml`. |
| `agents/` | 36 agent definitions + native TOML config. |
| `catalog/` | Prompt/skill catalog (incl. generated assets). |
| `runtime/`, `exec/` | Process runtime + command execution. |
| `sidecar/` | Sidecar process management. |
| `notifications/`, `openc*w/` | Notification gateway + integration (second dir name masked per house rule). |
| `hud/` | Read-only status HUD. |
| `session-history/` | Session log persistence + search. |
| `url-reader/`, `wiki/` | URL fetch + wiki lookups. |
| `imagegen/`, `visual/` | Image generation + visual verification. |
| `vscode/` | VS Code launch integration. |
| `auth/` | Auth handling. |
| `adapt/`, `compat/` | Adaptation + backward-compat shims. |
| `document-refresh/` | Refresh installed docs. |
| `utils/` | Shared helpers (incl. `platform-command.ts`). |
| `types/` | Shared TypeScript types. |
| `scripts/` | Notify-hook engine, eval scripts, fixtures. |

## Native crates (`crates/`)

| Crate | Purpose |
|-------|---------|
| `omx-sparkshell` | Interactive shell (backs `omx sparkshell`). |
| `omx-mux` | Pane/terminal multiplexer. |
| `omx-explore` | Fast code explorer (backs `omx explore`). |
| `omx-runtime` | Runtime host. |
| `omx-runtime-core` | Shared runtime primitives. |
| `omx-api` | Shared API contract crate. |

## Agents (36)

Installed as Codex slash-commands from `prompts/*.md`. Roles:

`analyst`, `api-reviewer`, `architect`, `build-fixer`, `code-reviewer`,
`code-simplifier`, `critic`, `debugger`, `dependency-expert`, `designer`,
`executor`, `explore`, `git-master`, `information-architect`,
`performance-reviewer`, `planner`, `product-analyst`, `product-manager`,
`prometheus-strict-metis`, `prometheus-strict-momus`,
`prometheus-strict-oracle`, `qa-tester`, `quality-reviewer`,
`quality-strategist`, `researcher`, `scholastic`, `security-reviewer`,
`style-reviewer`, `team-executor`, `test-engineer`, `ux-researcher`,
`verifier`, `vision`, `writer`.

Definitions live in `src/agents/definitions.ts`; prompt bodies in
`prompts/<name>.md`; the orchestration brain in `templates/AGENTS.md`.
