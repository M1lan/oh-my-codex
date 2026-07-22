# _common.just -- shared settings + variables, imported by the root Justfile
# and every module under .just/. Imports are textual: settings and variables
# defined here apply to the importing file.

set shell := ["/opt/homebrew/bin/bash", "-euo", "pipefail", "-c"]
set dotenv-load := false
set positional-arguments

pnpm_cmd := "source ~/.config/sh/fnm-init.sh >/dev/null 2>&1 || true; corepack enable >/dev/null 2>&1; pnpm"
repo_root := justfile_directory()
helpers := repo_root / ".just" / "helpers"
