# ── oh-my-codex Justfile -- modular, LLM-first, one human menu ──
#
# Root = entry + gates + frequent verbs. Depth lives in modules under .just/:
#
#   just              smart entry: agents/headless get the terse recipe dump,
#                     humans (zsh/fish on a tty) get the menu
#   just menu         the single human menu (splash + guided builder)
#   just help         plain recursive recipe list
#   just ci           FULL pre-push gate (TS + Rust + bash + just fmt)
#   just build        tsc            · just build full|explore|api|...
#   just test         fast node run  · just test full|compat-node|...
#   just lint         biome          · just lint md|typos|secrets|...
#   just rust         cargo build    · just rust test|lint|fmt|...
#   just omx          omx doctor     · just omx reinstall|sync-plugin|...
#   just ai           beads          · just ai cg "query"|ask-claude|...
#
# Recipes stay one-liners calling pnpm, cargo, or a helper under
# .just/helpers/ -- never inline logic, never a heredoc. Shared settings live
# in .just/_common.just (imported here and by every module).

import '.just/_common.just'

mod build '.just/build.just'
mod test '.just/test.just'
mod lint '.just/lint.just'
mod rust '.just/rust.just'
mod omx '.just/omx.just'
mod ai '.just/ai.just'

# ── Entry ──

# (default) terse recipe dump for agents/headless; menu for humans
[group('meta')]
[no-exit-message]
default:
    @'{{ helpers }}/entry.bash'

# The single human menu: splash header + guided command builder
[group('meta')]
[no-exit-message]
menu:
    @'{{ helpers }}/menu.bash'

# Plain recursive recipe list
[group('meta')]
help:
    @just --list --list-submodules --unsorted

# Project name + toolchain versions (script-friendly plain text)
[group('meta')]
version:
    @echo "oh-my-codex $(jq -r .version package.json)"
    @echo "node  $(node --version 2>/dev/null || echo 'not installed')"
    @echo "pnpm  $({{ pnpm_cmd }} --version 2>/dev/null || echo 'not installed')"
    @echo "cargo $(cargo --version 2>/dev/null || echo 'not installed')"

# Dependency + project health audit (tiers, versions, fixes)
[group('meta')]
doctor:
    @'{{ helpers }}/doctor.bash'

# Interactive installer for any missing dependency
[group('meta')]
[no-exit-message]
doctor-install:
    @'{{ helpers }}/doctor.bash' --install

# One-time dev setup: install node deps, then build
[group('meta')]
setup:
    {{ pnpm_cmd }} install
    {{ pnpm_cmd }} run build
    @echo "setup complete -- run 'just ci' to confirm the gate is green"

# ── Dev loop ──

# Watch-rebuild loop (tsc --watch)
[group('dev')]
[no-exit-message]
dev:
    {{ pnpm_cmd }} run dev

# Run the omx CLI from the build (just run -- doctor)
[group('dev')]
run *args:
    node dist/cli/omx.js {{ args }}

# Apply ALL formatters: biome + shfmt + just --fmt
[group('dev')]
fmt: lint::shfmt lint::justfmt
    {{ pnpm_cmd }} exec biome format --write src bin src/scripts

# ── Gates ──

# FULL pre-push gate: TS + Rust + bash helpers + just formatting
[group('gate')]
ci: ci-ts ci-rust lint::shellcheck lint::justfmt-check

# TypeScript gate (format + lint + typecheck + full tests + docs)
[group('gate')]
ci-ts: lint::fmt-check lint::biome lint::unused lint::pnpm test::full lint::md

# Rust gate (format + clippy + tests)
[group('gate')]
ci-rust: rust::fmt-check rust::lint rust::test

# ── Sync ──

# Fork flow: fetch upstream, merge into mymain, gate, build, reinstall
[group('sync')]
sync-upstream *flags:
    @'{{ helpers }}/sync-upstream.bash' {{ flags }}

# ── Human utilities ──

# rg the source tree -> pick a match in fzf -> open in $EDITOR
[group('util')]
[no-exit-message]
search query='':
    @'{{ helpers }}/search.bash' '{{ query }}'

# Fuzzy-pick a TS/Rust source file (bat preview) -> open in $EDITOR
[group('util')]
[no-exit-message]
pick:
    @'{{ helpers }}/pick.bash'

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
