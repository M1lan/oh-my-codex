# oh-my-codex -- one entry point.
#
#   make            bootstrap dev deps if needed, then hand over to `just`
#   make <target>   shorthand for `just <target>`  (e.g. `make test`)
#
# Why this file exists: a newcomer's reflex is to type `make`. That single
# command provisions the toolchain (brew base -> pnpm install -> tsc build ->
# cargo build) the first time, and on every run after that -- once everything
# is present -- hands straight to the `just` splash, fast and silent.
# Everything real lives in the Justfile and .just/helpers/; this is a thin
# 2-tier bootstrapper, nothing more.
.POSIX:

JUST := just

# First (default) target: bare `make`. bootstrap.bash is idempotent and
# detects an already-provisioned tree, in which case it `exec`s `just`.
bootstrap:
	@.just/helpers/bootstrap.bash

# Re-run the full install splash even when everything is present.
rebootstrap:
	@.just/helpers/bootstrap.bash --force

# Forward `make <goals>` to `just <goals>` EXACTLY ONCE. GNU make fires a
# pattern/`.DEFAULT` rule once per unmatched goal, each time passing the full
# goal list -- a naive catch-all double-runs `make a b`. Carry the whole list
# on the first goal and no-op the rest (gotcha #25). bootstrap/rebootstrap are
# filtered out so they keep their explicit recipes above.
FWD := $(filter-out bootstrap rebootstrap,$(MAKECMDGOALS))
ifneq ($(FWD),)
$(firstword $(FWD)): ; @$(JUST) $(FWD)
$(wordlist 2,$(words $(FWD)),$(FWD)): ; @:
endif

# Stop make from trying to remake the makefile itself via the rules above.
Makefile: ;

# Forwarded goals are tasks, not files -- never skip them as "up to date".
.PHONY: bootstrap rebootstrap $(MAKECMDGOALS)
