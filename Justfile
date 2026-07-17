# ── oh-my-codex Justfile -- pnpm + cargo, CI gates, guided launcher ──
#
# Thin by design: recipes are one-liners that call pnpm, cargo, or a helper
# under .just/helpers/. The splash, guided menu, doctor, and bootstrap live in
# those helpers -- never inline, never a heredoc.
#
#   just            full-screen splash + countdown (the default; START HERE)
#   just menu       guided command builder (parameters become forms)
#   just help       the plain `--list`
#   make            bootstrap deps if needed, then hand to `just`
#
# Every recipe carries a [group('...')] so the menu can categorize it from
# `just --dump`.

set shell := ["/opt/homebrew/bin/bash", "-euo", "pipefail", "-c"]
set dotenv-load := false
set positional-arguments := true

pnpm_cmd := "source ~/.config/sh/fnm-init.sh >/dev/null 2>&1 || true; corepack enable >/dev/null 2>&1; pnpm"
helpers := justfile_directory() / ".just" / "helpers"

# ── Meta & launchers ──

# (default) full-screen splash + countdown launcher
[group('meta')]
[no-exit-message]
default:
    @'{{helpers}}/info-screen.bash'

# Plain recipe list
[group('meta')]
help:
    @just --list --unsorted

# Project facts splash (static; no countdown)
[group('meta')]
info:
    @'{{helpers}}/info-screen.bash' --static

# Project name + toolchain versions (script-friendly plain text)
[group('meta')]
version:
    @echo "oh-my-codex $(jq -r .version package.json)"
    @echo "node  $(node --version 2>/dev/null || echo 'not installed')"
    @echo "pnpm  $({{pnpm_cmd}} --version 2>/dev/null || echo 'not installed')"
    @echo "cargo $(cargo --version 2>/dev/null || echo 'not installed')"

# Guided command builder (parameters become fill-in forms)
[group('meta')]
[no-exit-message]
menu:
    @'{{helpers}}/menu.bash'

# Dependency + project health audit (tiers, versions, fixes)
[group('meta')]
doctor:
    @'{{helpers}}/doctor.bash'

# Interactive installer for any missing dependency
[group('meta')]
[no-exit-message]
doctor-install:
    @'{{helpers}}/doctor.bash' --install

# One-time dev setup: install node deps, then build
[group('meta')]
setup:
    {{pnpm_cmd}} install
    {{pnpm_cmd}} run build
    @echo "setup complete -- run 'just ci' to confirm the gate is green"

# ── Build & Run ──

# Compile TypeScript to dist/ (tsc)
[group('build')]
build:
    {{pnpm_cmd}} run build

# Full build: TS + explore harness + sparkshell + api
[group('build')]
build-full:
    {{pnpm_cmd}} run build:full

# Build the Rust explore harness (debug)
[group('build')]
build-explore:
    {{pnpm_cmd}} run build:explore

# Watch-rebuild loop (tsc --watch)
[group('build')]
[no-exit-message]
dev:
    {{pnpm_cmd}} run dev

# Run the omx CLI from the build (just run -- doctor)
[group('run')]
run *args:
    node dist/cli/omx.js {{args}}

# Run the omx `setup` subcommand (installs the codex plugin payload)
[group('run')]
omx-setup:
    node dist/cli/omx.js setup

# ── Test ──

# Full test suite (build + verify + node tests + catalog check)
[group('test')]
test:
    {{pnpm_cmd}} run test

# Node tests only against the existing dist/ (fast inner loop)
[group('test')]
test-node:
    {{pnpm_cmd}} run test:node

# Explore-harness tests (cargo + node)
[group('test')]
test-explore:
    {{pnpm_cmd}} run test:explore

# Recent-bug regression suite
[group('test')]
test-regressions:
    {{pnpm_cmd}} run test:recent-bug-regressions

# Full TypeScript coverage report (c8)
[group('test')]
coverage:
    {{pnpm_cmd}} run coverage:ts:full

# Team-critical coverage gate (thresholds enforced)
[group('test')]
coverage-team:
    {{pnpm_cmd}} run coverage:team-critical

# ── Lint & Format ──

# Biome lint of the TypeScript sources (CI gate)
[group('lint')]
lint:
    {{pnpm_cmd}} run lint

# Apply Biome formatting to src/bin/scripts
[group('lint')]
fmt:
    {{pnpm_cmd}} exec biome format --write src bin src/scripts

# Check Biome formatting without writing
[group('lint')]
fmt-check:
    {{pnpm_cmd}} exec biome format src bin src/scripts

# Typecheck with the no-unused tsconfig (no emit)
[group('lint')]
check-unused:
    {{pnpm_cmd}} run check:no-unused

# Verify only pnpm is used as the package manager
[group('lint')]
check-pnpm:
    {{pnpm_cmd}} run check:no-npm

# Markdown lint
[group('lint')]
md-lint:
    @if command -v rumdl >/dev/null 2>&1; then rumdl check .; else echo "rumdl not installed -- skipping"; fi

# Spelling
[group('lint')]
typos:
    @if command -v typos >/dev/null 2>&1; then typos; else echo "typos not installed -- skipping"; fi

# Lint the bash helpers (shellcheck, warning severity)
[group('lint')]
shellcheck:
    @if command -v shellcheck >/dev/null 2>&1; then shellcheck -x -S warning -P {{helpers}} {{helpers}}/*.bash; else echo "shellcheck not installed -- skipping"; fi

# Format the bash helpers (shfmt, 2-space indent)
[group('lint')]
shfmt:
    @if command -v shfmt >/dev/null 2>&1; then shfmt -w -i 2 -ci {{helpers}}/*.bash; else echo "shfmt not installed -- skipping"; fi

# ── Rust workspace (cargo) ──

# Debug build of the Rust crates
[group('rust')]
rust-build:
    cargo build

# Release build of the Rust crates
[group('rust')]
rust-build-release:
    cargo build --release

# Run the Rust workspace tests
[group('rust')]
rust-test:
    cargo test

# Clippy across all targets, warnings are errors
[group('rust')]
rust-lint:
    cargo clippy --all-targets -- -D warnings

# Apply rustfmt
[group('rust')]
rust-fmt:
    cargo fmt

# Check rustfmt without writing
[group('rust')]
rust-fmt-check:
    cargo fmt --check

# ── Check & Verify (gates) ──

# Full CI gate (TS format + lint + typecheck + tests + docs)
[group('check')]
ci: fmt-check lint check-unused check-pnpm test md-lint

# Rust CI gate (format + clippy + tests)
[group('check')]
verify-rust: rust-fmt-check rust-lint rust-test

# Full pre-push gate: TS CI + Rust CI + bash-helper lint
[group('check')]
verify: ci verify-rust shellcheck

# Secret scan (full history)
[group('check')]
secrets:
    @if command -v gitleaks >/dev/null 2>&1; then gitleaks git --no-banner .; else echo "gitleaks not installed -- skipping"; fi

# ── Utilities ──

# rg the source tree -> pick a match in fzf -> open in $EDITOR
[group('util')]
[no-exit-message]
search-fzf query='':
    @'{{helpers}}/search.bash' '{{query}}'

# Fuzzy-pick a TS/Rust source file (bat preview) -> open in $EDITOR
[group('util')]
[no-exit-message]
pick:
    @'{{helpers}}/pick.bash'

# ── OMX Install / Uninstall ──

# Uninstall all global omx installations (pnpm global remove)
[group('omx')]
omx-uninstall:
    @'{{helpers}}/omx-install.bash' uninstall

# Install omx from this local checkout (pnpm add -g <abs-path>)
[group('omx')]
omx-install:
    @'{{helpers}}/omx-install.bash' install

# Uninstall then reinstall omx from this local checkout (full cycle)
[group('omx')]
omx-reinstall:
    @'{{helpers}}/omx-install.bash' reinstall

# ── Clean ──

# Remove the TypeScript build output
[group('clean')]
clean:
    rm -rf dist
    rm -f *.tsbuildinfo

# Remove all build output, caches, deps and Rust target
[group('clean')]
clean-all: clean
    rm -rf node_modules coverage target
