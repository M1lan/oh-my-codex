# omx module -- install/uninstall the CLI, plugin payload sync, bundle checks.
# `just omx` = omx CLI doctor (read-only).

import '_common.just'

set working-directory := '..'

# Run the omx CLI doctor against the build (read-only; module default)
[default]
doctor:
    node dist/cli/omx.js doctor

# Run the omx `setup` subcommand (installs the codex plugin payload)
setup:
    node dist/cli/omx.js setup

# Install omx from this local checkout (pnpm add -g <abs-path>)
install:
    @'{{ helpers }}/omx-install.bash' install

# Uninstall all global omx installations (pnpm global remove)
uninstall:
    @'{{ helpers }}/omx-install.bash' uninstall

# Uninstall then reinstall omx from this local checkout (full cycle)
reinstall:
    @'{{ helpers }}/omx-install.bash' reinstall

# Sync the codex plugin mirror (writes)
sync-plugin:
    {{ pnpm_cmd }} run sync:plugin

# Check the codex plugin mirror without writing
sync-plugin-check:
    {{ pnpm_cmd }} run sync:plugin:check

# Verify native agent definitions
verify-agents:
    {{ pnpm_cmd }} run verify:native-agents
