# ai module -- agent-facing utilities: beads tracker, codegraph, ask scripts,
# prompt inventory. `just ai` = open beads (read-only).

import '_common.just'

set working-directory := '..'

# Open beads in the br tracker (read-only; module default)
[default]
beads:
    @if command -v br >/dev/null 2>&1; then br list; else echo "skip: br not installed" >&2; fi

# Query the codegraph index (codegraph explore "<question or symbols>")
cg query:
    @codegraph explore "$1"

# Ask Claude via the omx CLI (just ai ask-claude "question")
ask-claude *args:
    node dist/cli/omx.js ask claude "$@"

# Ask Gemini via the omx CLI (just ai ask-gemini "question")
ask-gemini *args:
    node dist/cli/omx.js ask gemini "$@"

# Prompt inventory report
prompts:
    {{ pnpm_cmd }} run prompt:inventory
