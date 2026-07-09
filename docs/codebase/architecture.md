# Architecture

Diagrams render on GitHub (native Mermaid) and in
[`explorer.html`](./explorer.html). Everything below is derived from the
`codegraph` index and `ast-grep` queries against `src/`.

## 1. System context

Where `omx` sits between the user, the Codex CLI, and on-disk state.

```mermaid
flowchart TD
    U[User / terminal] --> OMX[omx CLI]
    OMX --> CFG["~/.codex/ config.toml, prompts, skills, AGENTS.md"]
    OMX --> CODEX[OpenAI Codex CLI]
    OMX --> STATE[".omx/ runtime state, plans, logs, memory"]
    CODEX --> MCP{MCP servers}
    MCP --> S1[omx-state]
    MCP --> S2[omx-memory]
    MCP --> S3[omx-wiki]
    MCP --> S4[omx-trace]
    MCP --> S5[omx-code-intel]
    MCP --> S6[omx-h* bridge]
    CODEX --> NATIVE[Rust crates: sparkshell, mux, explore]
    OMX -.installs/refreshes.-> CFG
```

## 2. Component map

The top-level `src/` subsystems and how they group. Boxes are directories
under `src/`.

```mermaid
flowchart LR
    subgraph Entry
        CLI[cli/ — omx command router]
        IDX[index.ts — library API]
    end
    subgraph Orchestration
        TEAM[team/ — multi-agent coordination]
        PIPE[pipeline/ — Autopilot stages]
        LEAD[leader/ — leader-side control]
        SUB[subagents/]
        MODES[modes/ + hooks/ — keyword→mode routing]
    end
    subgraph Workflows
        AUTO[autopilot/]
        RALPH[ralph/]
        RALPLAN[ralplan/]
        UG[ultragoal/]
        AR[autoresearch/]
        GW[goal-workflows/]
        PLAN[planning/]
        Q[question/]
        VERIF[verification/]
    end
    subgraph Platform
        MCP[mcp/ — 6 servers]
        STATE[state/ — workflow transitions]
        CFG[config/ — config.toml generation]
        AGENTS[agents/ — 36 definitions + native config]
        CATALOG[catalog/ — prompt/skill catalog]
        RUNTIME[runtime/ + exec/]
        SIDE[sidecar/]
    end
    subgraph IO
        NOTIF[notifications/ + openc*w/]
        HUD[hud/]
        SESS[session-history/]
        URL[url-reader/ + wiki/]
        IMG[imagegen/ + visual/]
        VSC[vscode/]
    end
    CLI --> Orchestration
    CLI --> Workflows
    CLI --> Platform
    Orchestration --> Platform
    Workflows --> Platform
    Platform --> IO
```

## 3. The Autopilot pipeline

The default orchestration loop (`src/pipeline/orchestrator.ts`,
`createAutopilotPipelineConfig`). Each stage is a `PipelineStage` with a
`StageContext` in / `StageResult` out; legacy `team` and `ralph-verify`
adapters remain selectable.

```mermaid
flowchart LR
    START([task]) --> DI[deep-interview<br/>clarify requirements]
    DI --> RP[ralplan<br/>consensus plan]
    RP --> UG[ultragoal<br/>ordered goal ledger]
    UG --> CR{code-review<br/>verdict}
    CR -->|APPROVE| QA{ultraqa<br/>run + fix tests}
    CR -->|ITERATE| UG
    QA -->|green| DONE([done])
    QA -->|failing| UG
    CR -->|REJECT| DI
```

Stage sources: `src/pipeline/stages/{deep-interview,ralplan,ultragoal,code-review,ultraqa}.ts`,
shared base in `stages/base.ts`, types in `pipeline/types.ts`.

## 4. Team orchestration

`team/` runs a leader plus N workers across tmux panes. Workers can be
Codex or Claude (`OMX_TEAM_WORKER_CLI_MAP`). A DAG schedules tasks;
policies decide allocation, delegation, and commit hygiene.

```mermaid
flowchart TD
    TC[cli/team.ts] --> ORCH[team leader]
    ORCH --> DAG[dag-schema.ts<br/>task DAG]
    ORCH --> ALLOC[allocation-policy.ts]
    ORCH --> DELEG[delegation-policy.ts]
    ORCH --> MODEL[model-contract.ts]
    ORCH --> COORD[coordination-protocol.ts]
    COORD --> COMM[mcp-comm.ts<br/>leader↔worker]
    ORCH --> TMUX[tmux-session.ts<br/>panes via rmux/tmux]
    subgraph Workers
        W1[worker pane 1]
        W2[worker pane 2]
        W3[worker pane N]
    end
    COMM --> W1
    COMM --> W2
    COMM --> W3
    W1 --> BASE[current-task-baseline.ts]
    ORCH --> IDLE[idle-nudge.ts + leader-activity.ts]
    ORCH --> COMMIT[commit-hygiene.ts]
    ORCH --> FOLLOW[followup-planner.ts]
```

`api-interop.ts` (the largest team file, ~55 KB) is the cross-CLI API
contract that lets Codex and Claude workers speak the same protocol; the
`setup` verifier checks its markers (`verifyTeamCliApiInterop`).

## 5. MCP servers

Six servers registered into Codex via `config.toml`. `bootstrap.ts` wires
them up; `state-paths.ts` centralizes on-disk locations.

```mermaid
flowchart LR
    BOOT[mcp/bootstrap.ts] --> ST[omx-state<br/>state-server.ts<br/>lifecycle, notepad]
    BOOT --> MEM[omx-memory<br/>memory-server.ts<br/>project memory]
    BOOT --> WIKI[omx-wiki<br/>wiki-server.ts]
    BOOT --> TR[omx-trace<br/>trace-server.ts<br/>debug traces]
    BOOT --> CI[omx-code-intel<br/>code-intel-server.ts]
    BOOT --> HB[omx-h* bridge<br/>h*-bridge.ts + h*-server.ts]
    ST --> PATHS[state-paths.ts]
    MEM --> PATHS
    PATHS --> DISK[".omx/ on disk"]
```

## 6. Mode / keyword routing

User phrasing selects a workflow mode. `hooks/keyword-detector.ts` (the
single biggest hook, ~76 KB) matches against `keyword-registry.ts` and the
active-skill state, then drives `state/workflow-transition.ts`.

```mermaid
flowchart TD
    IN[user prompt] --> KD[hooks/keyword-detector.ts]
    KD --> KR[keyword-registry.ts]
    KD --> SK[state/skill-active.ts]
    KD --> MODE{resolved mode}
    MODE --> autopilot
    MODE --> team
    MODE --> ralph
    MODE --> ralplan
    MODE --> ultragoal
    MODE --> ultraqa
    MODE --> ultrawork
    MODE --> plan
    MODE --> deep-interview
    MODE --> autoresearch
    MODE --> WT[state/workflow-transition.ts]
    WT --> OPS[state/operations.ts<br/>persist mode state]
```

## 7. Native runtime (Rust)

Six crates under `crates/`, built by `pnpm build:sparkshell` /
`build:explore`. They provide the fast interactive shell and code
exploration that back `omx sparkshell` and `omx explore`.

```mermaid
flowchart LR
    SPARK[omx-sparkshell<br/>interactive shell] --> RT[omx-runtime]
    RT --> RTC[omx-runtime-core]
    MUX[omx-mux<br/>pane multiplexer] --> RTC
    EXP[omx-explore<br/>code explorer] --> RTC
    API[omx-api<br/>shared contract] --> RTC
    SPARK -.spawns via.-> TS[cli/sparkshell.ts]
    EXP -.invoked by.-> TSX[cli/explore.ts]
```

TypeScript talks to these binaries through `utils/platform-command.ts`,
which now routes bare `tmux` spawns through the `rmux` multiplexer shim
before falling back to real `tmux`.
