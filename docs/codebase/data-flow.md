# Data flow

Sequence diagrams for the flows a maintainer hits most. Rendered by
GitHub and by [`explorer.html`](./explorer.html).

## Session launch (`omx`)

From invocation to a running Codex session with OMX config applied.

```mermaid
sequenceDiagram
    actor User
    participant OMX as omx (cli/index.ts)
    participant Setup as cli/setup.ts
    participant Cfg as config/generator.ts
    participant Codex as Codex CLI
    User->>OMX: omx [--madmax] [flags]
    OMX->>OMX: parse args, resolve mode
    OMX->>Setup: ensure ~/.codex is current
    Setup->>Cfg: mergeConfig(config.toml)
    Cfg-->>Setup: merged config + MCP block
    Setup->>Setup: install prompts, skills, AGENTS.md
    OMX->>Codex: launchDirectSession(argv, env)
    Codex->>Codex: load AGENTS.md brain + MCP servers
    Codex-->>User: interactive session
```

## Autopilot pipeline run

How one task threads through the five stages.

```mermaid
sequenceDiagram
    participant Orch as pipeline/orchestrator.ts
    participant DI as deep-interview
    participant RP as ralplan
    participant UG as ultragoal
    participant CR as code-review
    participant QA as ultraqa
    participant State as state/operations.ts
    Orch->>State: readPipelineState()
    Orch->>DI: run(StageContext)
    DI-->>Orch: requirements
    Orch->>RP: run(ctx)
    RP-->>Orch: plan file
    loop until approved & green
        Orch->>UG: run(ctx)
        UG-->>Orch: goals executed
        Orch->>CR: run(ctx)
        CR-->>Orch: verdict (APPROVE/ITERATE/REJECT)
        Orch->>QA: run(ctx)
        QA-->>Orch: test verdict
    end
    Orch->>State: persist result
```

## Team run

Leader spawns workers, distributes DAG tasks, collects results.

```mermaid
sequenceDiagram
    actor User
    participant Team as cli/team.ts
    participant Lead as team leader
    participant Tmux as team/tmux-session.ts
    participant Comm as team/mcp-comm.ts
    participant W as worker pane
    User->>Team: $team "goal"
    Team->>Lead: build DAG (dag-schema.ts)
    Lead->>Tmux: create session + N panes (rmux/tmux)
    Tmux-->>Lead: pane targets
    Lead->>Comm: assign task (allocation-policy.ts)
    Comm->>W: dispatch via MCP
    W->>W: execute in Codex/Claude
    W-->>Comm: result + delivery-log.ts
    Comm-->>Lead: completion
    Lead->>Lead: commit-hygiene.ts + followup-planner.ts
    Lead-->>User: summary
```

## MCP state read/write

How a running session persists and recalls lifecycle state.

```mermaid
sequenceDiagram
    participant Codex as Codex session
    participant ST as omx-state (state-server.ts)
    participant Paths as state-paths.ts
    participant Disk as .omx/ on disk
    Codex->>ST: tool call (get/set state, notepad)
    ST->>Paths: resolve project state path
    Paths-->>ST: absolute path under .omx/
    ST->>Disk: read/write JSON
    Disk-->>ST: state payload
    ST-->>Codex: result
    Note over Codex,Disk: omx-memory + omx-trace follow the same shape
```

## Mode resolution on each prompt

The hook that decides which workflow a message triggers.

```mermaid
sequenceDiagram
    participant Prompt as user message
    participant KD as hooks/keyword-detector.ts
    participant Reg as keyword-registry.ts
    participant Skill as state/skill-active.ts
    participant WT as state/workflow-transition.ts
    Prompt->>KD: text
    KD->>Reg: match keywords
    KD->>Skill: current active skill?
    KD->>KD: score candidates
    KD->>WT: transition(mode)
    WT->>WT: reconcile (workflow-transition-reconcile.ts)
    WT-->>Prompt: mode applied
```
