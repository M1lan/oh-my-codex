#!/usr/bin/env bash
# sync-upstream.bash -- the mymain fork flow, one command:
#
#   fetch origin+upstream -> ff origin/mymain if behind -> merge upstream/main
#   into mymain -> just ci -> build -> omx reinstall -> verify installed version
#
#   sync-upstream.bash              full flow
#   sync-upstream.bash --dry-run    print what would happen, change nothing
#   sync-upstream.bash --no-install skip the final omx reinstall
#
# Safety contract (never stash, reset, rebase, force, or push):
#   * abort BEFORE touching anything: dirty tree, not on mymain, missing
#     remotes, a git operation already in progress (merge/rebase/cherry-pick/
#     revert/bisect)
#   * origin/mymain diverged from local -> abort (origin-ahead-only fast-
#     forwards; local-ahead-only is fine)
#   * merge conflict -> `git merge --abort`, nothing else runs
#   * red `just ci` -> merge commit KEPT for diagnosis, no build/install
#   * reinstall verified: pnpm-global omx must report the checkout's version
# LLM-first output: one line per phase to stderr, quiet success.

# shellcheck source=lib.bash disable=SC2154,SC1091
source "$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)/lib.bash"
cd "$REPO_ROOT" || exit 1

DRY=0 INSTALL=1
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY=1 ;;
    --no-install) INSTALL=0 ;;
    *) die "usage: sync-upstream.bash [--dry-run] [--no-install]" ;;
  esac
done

phase() { printf 'sync-upstream: %s\n' "$*" >&2; }
run() {
  if ((DRY)); then
    printf 'dry-run: %s\n' "$*" >&2
  else
    "$@"
  fi
}

# ── preflight (read-only; every abort leaves the repo untouched) ─────────
branch=$(git rev-parse --abbrev-ref HEAD)
[[ "$branch" == "mymain" ]] || die "abort: on '$branch', expected mymain"
[[ -z "$(git status --porcelain)" ]] || die "abort: working tree dirty -- commit or stash first"
git remote get-url origin >/dev/null 2>&1 || die "abort: no 'origin' remote configured"
git remote get-url upstream >/dev/null 2>&1 || die "abort: no 'upstream' remote configured"
for marker in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply BISECT_LOG; do
  [[ ! -e "$(git rev-parse --git-path "$marker")" ]] || die "abort: git operation in progress ($marker)"
done

phase "fetch origin + upstream"
export GIT_TERMINAL_PROMPT=0
run git fetch --prune origin
run git fetch --prune upstream

changed=0
merge_needed=1
if ((!DRY)); then
  # origin/mymain: equal or behind us is fine; ahead-only fast-forwards;
  # diverged needs a human
  if git rev-parse -q --verify origin/mymain >/dev/null; then
    if git merge-base --is-ancestor origin/mymain mymain; then
      : # local is equal to or ahead of origin
    elif git merge-base --is-ancestor mymain origin/mymain; then
      phase "fast-forwarding to origin/mymain"
      run git merge --ff-only origin/mymain
      changed=1
    else
      die "abort: mymain and origin/mymain diverged -- reconcile by hand"
    fi
  fi
  behind=$(git rev-list --count mymain..upstream/main)
  if ((behind == 0)); then
    merge_needed=0
    if ((!changed)); then
      phase "already up to date -- nothing to do"
      exit 0
    fi
    phase "up to date with upstream/main; checkout changed by fast-forward -- gating"
  else
    phase "merging $behind upstream commit(s) into mymain"
  fi
fi

if ((merge_needed)); then
  if ! run git merge --no-edit upstream/main; then
    run git merge --abort || phase "warning: merge --abort also failed -- inspect by hand"
    die "abort: upstream merge conflicted and was aborted -- resolve by hand, then rerun"
  fi
fi

phase "gate: just ci"
run just ci || die "abort: ci gate red after merge -- merge KEPT; fix, then rerun"

phase "build"
run just build

if ((INSTALL)); then
  phase "reinstall omx from this checkout"
  run just omx reinstall
  if ((!DRY)); then
    # verify the pnpm-global binary (NOT `command -v omx` -- shims may shadow)
    global_bin=$(cd "$HOME" && pnpm bin -g 2>/dev/null) || die "abort: pnpm bin -g failed"
    [[ -x "$global_bin/omx" ]] || die "abort: global omx missing at $global_bin/omx"
    expected=$(jq -r .version package.json)
    actual=$("$global_bin/omx" --version 2>/dev/null | head -1)
    [[ "$actual" == *"$expected"* ]] || die "abort: installed omx reports '$actual', expected $expected"
    phase "installed omx verified at v$expected"
  fi
else
  phase "skipping install (--no-install)"
fi

phase "done"
