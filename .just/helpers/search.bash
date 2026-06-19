#!/usr/bin/env bash
# search.bash -- grep the source tree with rg, pick a match in fzf, open in $EDITOR.
# Usage: search.bash [query]
# shellcheck source=lib.bash disable=SC1091
source "$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)/lib.bash"
cd "$REPO_ROOT" || exit 1
trap 'exit 130' INT TERM HUP

has fzf || die "fzf not installed (run: just doctor-install)"
has rg || die "rg not installed (run: just doctor-install)"
has bat || die "bat not installed (run: just doctor-install)"

query="${1:-}"
match="$(rg --line-number --no-heading --color=always "$query" src crates 2>/dev/null |
  fzf --ansi --delimiter=: \
    --preview 'bat --color=always --style=numbers --highlight-line {2} {1}' || true)"
[[ -z "$match" ]] && exit 0
IFS=: read -r file line _ <<<"$match"
"${EDITOR:-vim}" "+${line:-1}" "$file" 2>/dev/null || "${EDITOR:-vim}" "$file"
