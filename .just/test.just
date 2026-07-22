# test module -- `just test` = fast node tests against existing dist/ (inner
# loop); `just test full` = the whole suite. Everything else by name.

import '_common.just'

set working-directory := '..'

# Node tests against the existing dist/ (fast inner loop; module default)
[default]
node:
    {{ pnpm_cmd }} run test:node

# Full test suite (build + verify + node tests + catalog check)
full:
    {{ pnpm_cmd }} run test

# Explore-harness tests (cargo + node)
explore:
    {{ pnpm_cmd }} run test:explore

# Recent-bug regression suite
regressions:
    {{ pnpm_cmd }} run test:recent-bug-regressions

# Node/TS compat suite (builds first)
compat-node:
    {{ pnpm_cmd }} run test:compat:node

# Rust-binary compat suite (cargo build + node compat against target/debug/omx)
compat-rust:
    {{ pnpm_cmd }} run test:compat:rust

# Sparkshell tests
sparkshell:
    {{ pnpm_cmd }} run test:sparkshell

# Team: cross-rebase smoke (builds first)
team-rebase:
    {{ pnpm_cmd }} run test:team:cross-rebase-smoke

# Team: worker runtime identity (builds first)
team-identity:
    {{ pnpm_cmd }} run test:team:worker-runtime-identity

# Reply-listener LIVE test -- SENDS REAL MESSAGES to a live session
reply-live:
    {{ pnpm_cmd }} run test:reply-listener:live

# Full TypeScript coverage report (c8)
coverage:
    {{ pnpm_cmd }} run coverage:ts:full

# Team-critical coverage gate (thresholds enforced)
coverage-team:
    {{ pnpm_cmd }} run coverage:team-critical

# Smoke-test a packed npm install
smoke:
    {{ pnpm_cmd }} run smoke:packed-install
