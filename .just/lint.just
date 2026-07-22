# lint module -- `just lint` = biome over the TS sources; the rest by name.
# Optional linters (rumdl, typos, shellcheck, gitleaks) skip with a one-line
# note when not installed -- never fail the gate for a missing optional tool.

import '_common.just'

set working-directory := '..'

# Biome lint of the TypeScript sources (CI gate; module default)
[default]
biome:
    {{ pnpm_cmd }} run lint

# Check Biome formatting without writing
fmt-check:
    {{ pnpm_cmd }} exec biome format src bin src/scripts

# Typecheck with the no-unused tsconfig (no emit)
unused:
    {{ pnpm_cmd }} run check:no-unused

# Verify only pnpm is used as the package manager
pnpm:
    {{ pnpm_cmd }} run check:no-npm

# Markdown lint
md:
    @if command -v rumdl >/dev/null 2>&1; then rumdl check .; else echo "skip: rumdl not installed" >&2; fi

# Spelling
typos:
    @if command -v typos >/dev/null 2>&1; then typos; else echo "skip: typos not installed" >&2; fi

# Lint the bash helpers (shellcheck, warning severity)
shellcheck:
    @if command -v shellcheck >/dev/null 2>&1; then shellcheck -x -S warning -P '{{ helpers }}' '{{ helpers }}'/*.bash; else echo "skip: shellcheck not installed" >&2; fi

# Format the bash helpers (shfmt, 2-space indent)
shfmt:
    @if command -v shfmt >/dev/null 2>&1; then shfmt -w -i 2 -ci '{{ helpers }}'/*.bash; else echo "skip: shfmt not installed" >&2; fi

# Check Justfile + module formatting (just --fmt --check)
justfmt-check:
    @for f in Justfile .just/*.just; do just --fmt --check --unstable --justfile "$f" || exit 1; done

# Apply canonical formatting to Justfile + modules
justfmt:
    @for f in Justfile .just/*.just; do just --fmt --unstable --justfile "$f"; done

# Secret scan (full git history)
secrets:
    @if command -v gitleaks >/dev/null 2>&1; then gitleaks git --no-banner .; else echo "skip: gitleaks not installed" >&2; fi
