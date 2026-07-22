# rust module -- cargo workspace. `just rust` = debug build.

import '_common.just'

set working-directory := '..'

# Debug build of the Rust crates (module default)
[default]
build:
    cargo build

# Release build of the Rust crates
release:
    cargo build --release

# Run the Rust workspace tests
test:
    cargo test

# Clippy across all targets, warnings are errors
lint:
    cargo clippy --all-targets -- -D warnings

# Apply rustfmt
fmt:
    cargo fmt

# Check rustfmt without writing
fmt-check:
    cargo fmt --check
