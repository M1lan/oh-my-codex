# build module -- `just build` compiles TS; `just build <recipe>` for the rest.

import '_common.just'

set working-directory := '..'

# Compile TypeScript to dist/ (tsc; module default)
[default]
ts:
    {{ pnpm_cmd }} run build

# Full build: TS + explore harness + sparkshell + api
full:
    {{ pnpm_cmd }} run build:full

# Build the Rust explore harness (debug)
explore:
    {{ pnpm_cmd }} run build:explore

# Build the Rust explore harness (release)
explore-release:
    {{ pnpm_cmd }} run build:explore:release

# Build the API surface (dist/scripts/build-api.js)
api:
    {{ pnpm_cmd }} run build:api

# Build the sparkshell bundle
sparkshell:
    {{ pnpm_cmd }} run build:sparkshell
